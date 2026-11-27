#!/usr/bin/env python3
# Builds the player mods override pk3 from the recipes in tools/player_mods/override/.
#
# Some mods clash (two mods shipping the same model dir or .bot file). A recipe says how to fix
# one clash: which mod pk3 to read, which of its files to copy under a new path, which npc keys
# to change, which committed files (a .bot) to add. Only the recipes are in the repo; the mods'
# own files are read from the players dir when the pk3 is built, as zips (nothing is extracted
# or run). The result is one pk3, OVERRIDE_PK3, whose name sorts after every mod pk3 in the
# engine's FS_PathCmp order, so its files win.
#
# Recipe lines (# starts a comment, paths may not hold spaces except in `from`):
#   needs  <mod dir> [<mod dir> ...]   the recipe applies only when all of them are installed
#   from   <mod dir>/<pk3>             the source pk3 for the lines below (rest of the line)
#   rename <old prefix> <new prefix>   copy the source's files under <old prefix> to <new prefix>
#   copy   <path> <new path>           copy one file of the source
#   set    <file> <entry> <key> <value>  set a key of an npc / bot entry in a copied file
#   file   <path in pk3> <file>        add a file committed next to the recipe
# Copied text files get every reference to a renamed file (<old prefix><name>, any extension)
# rewritten to its new path; references to files the source does not ship are left alone.
#
# Usage examples:
#   build the pk3 for every recipe into a dir:
#     python3 -I build_overrides.py --out /tmp/overrides
#   players dir positional / named:
#     python3 -I build_overrides.py ~/Downloads/star_wars_ja_mods/players --out /tmp/o
#   only the recipes whose mods are all installed (what the install scripts pass):
#     python3 -I build_overrides.py --out /tmp/o --mods BabyYoda,DinDjarin
#   list what the recipes would do, build nothing:
#     python3 -I build_overrides.py --list
#   print the equivalent shell commands instead of building:
#     python3 -I build_overrides.py --out /tmp/o --debug

import argparse
import os
import re
import shlex
import sys
import zipfile

def _enable_windows_ansi():
	if os.name != "nt":
		return
	try:
		import ctypes
		k = ctypes.windll.kernel32
		h = k.GetStdHandle(-11)
		mode = ctypes.c_uint32()
		if k.GetConsoleMode(h, ctypes.byref(mode)):
			k.SetConsoleMode(h, mode.value | 0x0004)
	except Exception:
		pass

_enable_windows_ansi()
USE_COLOR = sys.stdout.isatty()
def _c(code, t): return f"\033[{code}m{t}\033[0m" if USE_COLOR else t
def print_header(t): print(_c("1;36", t))
def print_ok(t):     print(_c("32", t))
def print_warn(t):   print(_c("33", t))
def print_err(t):    print(_c("31", t), file=sys.stderr)
def print_key(k, v): print(f"  {_c('1;34', k + ':')} {v}")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RECIPE_DIR = os.path.join(SCRIPT_DIR, "override")
RECIPE_EXT = ".recipe"
# '~' sorts after every letter, digit and '_' in FS_PathCmp (letters are folded to upper case,
# so a name of z's still loses to "zzzzzz_..."): the override pk3 is searched first
OVERRIDE_PK3 = "~playermods_overrides.pk3"
DEFAULT_PLAYERS_SUBDIR = os.path.join("Downloads", "star_wars_ja_mods", "players")
TEXT_EXTS = (".skin", ".npc", ".shader", ".cfg", ".bot", ".sab", ".txt", ".jkb")
TEXT_ENCODING = "latin-1"
ZIP_TIME = (1980, 1, 1, 0, 0, 0)  # fixed: the same recipes and mods give the same bytes

class Recipe:
	def __init__(self, path):
		self.path = path
		self.name = os.path.splitext(os.path.basename(path))[0]
		self.needs, self.steps = [], []  # steps: (kind, source pk3 or None, args)
		source = None
		with open(path, encoding="utf-8") as f:
			for n, line in enumerate(f, 1):
				line = line.split("#", 1)[0].strip()
				if not line:
					continue
				kw, _, rest = line.partition(" ")
				kw, rest = kw.lower(), rest.strip()
				if kw == "needs":
					self.needs += rest.split()
				elif kw == "from":
					source = rest
				elif kw in ("rename", "copy", "set", "file"):
					args = rest.split()
					want = {"rename": 2, "copy": 2, "set": 4, "file": 2}[kw]
					if len(args) != want:
						raise ValueError(f"{path}:{n}: {kw} takes {want} arguments")
					if kw in ("rename", "copy", "set") and not source:
						raise ValueError(f"{path}:{n}: {kw} before any from")
					self.steps.append((kw, None if kw == "file" else source, args))
				else:
					raise ValueError(f"{path}:{n}: unknown keyword {kw}")

	def applies(self, mods):
		return mods is None or all(m.lower() in mods for m in self.needs)

def read_recipes():
	if not os.path.isdir(RECIPE_DIR):
		return []
	return [Recipe(os.path.join(RECIPE_DIR, f)) for f in sorted(os.listdir(RECIPE_DIR)) if f.endswith(RECIPE_EXT)]

def zip_names(z):
	"""lower-case name -> real name, files only"""
	return {i.filename.replace("\\", "/").lower(): i.filename for i in z.infolist() if not i.is_dir()}

def rewrite_refs(text, renames):
	"""renames: [(old prefix, new prefix, {base name lower})]; rewrites old/<base>.<any ext>"""
	for old, new, bases in renames:
		pattern = re.compile(re.escape(old) + r"([A-Za-z0-9_\-\.]+)", re.IGNORECASE)
		def sub(m):
			base = os.path.splitext(m.group(1))[0].lower()
			return (new + m.group(1)) if base in bases else m.group(0)
		text = pattern.sub(sub, text)
	return text

def set_key(text, entry, key, value):
	"""sets `key value` inside the top-level block `entry { ... }` (adds the key if missing)"""
	lines = text.split("\n")
	i, n = 0, len(lines)
	while i < n:
		tok = lines[i].split("//", 1)[0].strip()
		if tok.lower() == entry.lower() or tok.lower() == entry.lower() + " {":
			j = i if "{" in tok else i + 1
			while j < n and "{" not in lines[j]:
				j += 1
			k = j + 1
			while k < n and not lines[k].strip().startswith("}"):
				parts = lines[k].split()
				if parts and parts[0].lower() == key.lower():
					cr = "\r" if lines[k].endswith("\r") else ""
					lines[k] = f"\t{parts[0]}\t{value}{cr}"
					return "\n".join(lines), True
				k += 1
			if k < n:
				cr = "\r" if lines[j].endswith("\r") else ""
				lines.insert(j + 1, f"\t{key}\t{value}{cr}")
				return "\n".join(lines), True
		i += 1
	return text, False

def build(recipes, players, mods, out_dir, quiet=False):
	"""Returns the path of the pk3, or None when no recipe applies."""
	files = {}   # pk3 path -> bytes
	applied = []
	for r in recipes:
		if not r.applies(mods):
			if not quiet:
				print_key(f"skipped {r.name}", f"needs {', '.join(r.needs) or 'nothing'}")
			continue
		renames, out = [], {}
		opened = {}
		def src(rel):
			if rel not in opened:
				opened[rel] = zipfile.ZipFile(os.path.join(players, rel))
			return opened[rel]
		for kind, source, args in r.steps:
			if kind == "rename":
				z = src(source)
				names = zip_names(z)
				old, new = args[0].lower(), args[1]
				moved = [(low, real) for low, real in names.items() if low.startswith(old)]
				if not moved:
					raise ValueError(f"{r.name}: nothing under {args[0]} in {source}")
				renames.append((args[0], new, {os.path.splitext(low[len(old):])[0] for low, _ in moved}))
				for low, real in moved:
					out[new + real[len(old):]] = z.read(real)
			elif kind == "copy":
				z = src(source)
				names = zip_names(z)
				if args[0].lower() not in names:
					raise ValueError(f"{r.name}: {args[0]} not in {source}")
				out[args[1]] = z.read(names[args[0].lower()])
			elif kind == "file":
				with open(os.path.join(RECIPE_DIR, args[1]), "rb") as f:
					out[args[0]] = f.read()
		for path in list(out):
			if path.lower().endswith(TEXT_EXTS):
				text = out[path].decode(TEXT_ENCODING)
				out[path] = rewrite_refs(text, renames).encode(TEXT_ENCODING)
		for kind, _, args in r.steps:
			if kind == "set":
				if args[0] not in out:
					raise ValueError(f"{r.name}: set on {args[0]}, which the recipe does not copy")
				text, ok = set_key(out[args[0]].decode(TEXT_ENCODING), args[1], args[2], args[3])
				if not ok:
					raise ValueError(f"{r.name}: no entry {args[1]} in {args[0]}")
				out[args[0]] = text.encode(TEXT_ENCODING)
		for z in opened.values():
			z.close()
		for path in out:
			if path.lower() in {p.lower() for p in files}:
				raise ValueError(f"{r.name}: {path} is written by another recipe too")
		files.update(out)
		applied.append(r.name)
		if not quiet:
			print_key(f"recipe {r.name}", f"{len(out)} file(s)")
	if not files:
		return None
	os.makedirs(out_dir, exist_ok=True)
	pk3 = os.path.join(out_dir, OVERRIDE_PK3)
	# the engine lists a pk3 dir (FS_GetFileList "models/players" "/", the ui's model grid) only
	# from an explicit dir entry, so every parent dir of a file gets one
	dirs = {path[:i + 1] for path in files for i, ch in enumerate(path) if ch == "/"}
	with zipfile.ZipFile(pk3, "w", zipfile.ZIP_DEFLATED) as z:
		for d in sorted(dirs, key=str.lower):
			info = zipfile.ZipInfo(d, ZIP_TIME)
			info.external_attr = (0o40755 << 16) | 0x10
			z.writestr(info, b"")
		for path in sorted(files, key=str.lower):
			info = zipfile.ZipInfo(path, ZIP_TIME)
			info.compress_type = zipfile.ZIP_DEFLATED
			info.external_attr = 0o644 << 16
			z.writestr(info, files[path])
	if not quiet:
		print_ok(f"built {pk3}: {len(files)} file(s) from {', '.join(applied)}")
	return pk3

def debug_commands(recipes, players, mods, out_dir):
	"""bash: extract each recipe's files into a staging dir, rename, edit, zip"""
	q = shlex.quote
	stage = os.path.join(out_dir, "stage")
	lines = [f"# {' '.join(sys.argv)}", f"rm -rf {q(stage)} && mkdir -p {q(stage)}"]
	for r in recipes:
		if not r.applies(mods):
			lines.append(f"# {r.name}: skipped, needs {' '.join(r.needs)}")
			continue
		lines.append(f"# {r.name}")
		for kind, source, args in r.steps:
			src = q(os.path.join(players, source)) if source else ""
			if kind == "rename":
				tmp = os.path.join(out_dir, "x")
				lines.append(f"rm -rf {q(tmp)} && unzip -q -C {src} {q(args[0] + '*')} -d {q(tmp)} && mkdir -p {q(os.path.join(stage, args[1]))} && cp -r {q(tmp)}/{q(args[0])}* {q(os.path.join(stage, args[1]))}")
				lines.append(f"# then every {args[0]}<file shipped> in the copied text files -> {args[1]}<file>")
			elif kind == "copy":
				lines.append(f"mkdir -p {q(os.path.dirname(os.path.join(stage, args[1])))} && unzip -p -C {src} {q(args[0])} > {q(os.path.join(stage, args[1]))}")
			elif kind == "set":
				lines.append(f"# set {args[2]} {args[3]} in entry {args[1]} of {args[0]}")
			elif kind == "file":
				lines.append(f"mkdir -p {q(os.path.dirname(os.path.join(stage, args[0])))} && cp {q(os.path.join(RECIPE_DIR, args[1]))} {q(os.path.join(stage, args[0]))}")
	lines.append(f"(cd {q(stage)} && rm -f ../{q(OVERRIDE_PK3)} && zip -q -r -X ../{q(OVERRIDE_PK3)} .)")
	return "\n".join(lines)

def main():
	ap = argparse.ArgumentParser(description="Build the player mods override pk3 from tools/player_mods/override/*.recipe.")
	ap.add_argument("players_pos", nargs="?", metavar="PLAYERS_DIR")
	ap.add_argument("--players", "-p", help=f"players dir (default ~/{DEFAULT_PLAYERS_SUBDIR})")
	ap.add_argument("--out", "-o", help=f"dir to write {OVERRIDE_PK3} into")
	ap.add_argument("--mods", "-m", help="comma-separated installed mod dirs: only recipes needing a subset apply (case-insensitive)")
	ap.add_argument("--list", "-l", action="store_true", help="list the recipes, build nothing")
	ap.add_argument("--quiet", "-q", action="store_true", help="print only the built pk3's path")
	ap.add_argument("--no-color", action="store_true")
	ap.add_argument("--debug", "-d", action="store_true", help="print the equivalent shell commands instead")
	args = ap.parse_args()
	global USE_COLOR
	if args.no_color:
		USE_COLOR = False
	home = os.environ.get("USERPROFILE") if os.name == "nt" else os.path.expanduser("~")
	players = os.path.abspath(os.path.expanduser(args.players or args.players_pos or os.path.join(home or "", DEFAULT_PLAYERS_SUBDIR)))
	mods = None if args.mods is None else {m.strip().lower() for m in args.mods.split(",") if m.strip()}
	try:
		recipes = read_recipes()
	except ValueError as e:
		print_err(str(e))
		return 1
	if args.list:
		for r in recipes:
			state = "applies" if r.applies(mods) else "skipped"
			print_header(f"{r.name} ({state}): needs {', '.join(r.needs) or 'nothing'}")
			for kind, source, a in r.steps:
				print(f"  {kind} {' '.join(a)}" + (f"   (from {source})" if source else ""))
		return 0
	if not args.out:
		ap.error("give --out <dir> (or --list)")
	out_dir = os.path.abspath(os.path.expanduser(args.out))
	if args.debug:
		print(debug_commands(recipes, players, mods, out_dir))
		return 0
	try:
		pk3 = build(recipes, players, mods, out_dir, args.quiet)
	except (ValueError, OSError, zipfile.BadZipFile) as e:
		print_err(f"override pk3 not built: {e}")
		return 1
	if args.quiet and pk3:
		print(pk3)
	elif not pk3 and not args.quiet:
		print_warn("no recipe applies: nothing built")
	return 0

if __name__ == "__main__":
	sys.exit(main())
