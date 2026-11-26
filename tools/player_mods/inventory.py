#!/usr/bin/env python3
# Inventory of Jedi Academy player model mods.
#
# Reads every mod dir under the players dir (one dir per mod, holding its pk3(s), a readme and
# screenshots) and lists per mod: its pk3s, model dirs, skins, .npc / .bot / .jkb / .sab names,
# custom .gla, SP menu files, the scale / height / width keys of its .npc entries, the stock
# files it overrides (checked against the install's base/assets*.pk3) and the files it shares
# with other mods, plus which pk3 wins such a file once everything sits in one base/ dir.
#
# The pk3s are only read as zips: nothing is extracted and nothing from them is run. Run it with
# `python3 -I` (the scripts in this dir do).
#
# Usage examples:
#   python3 -I inventory.py                                   # all mods, default players dir
#   python3 -I inventory.py ~/Downloads/star_wars_ja_mods/players
#   python3 -I inventory.py --players <dir> --game ~/.local/share/openjk/JediAcademy
#   python3 -I inventory.py --mod yoda                        # only mods whose dir matches "yoda"
#   python3 -I inventory.py --mod T_Yoda -c                   # case-sensitive match
#   python3 -I inventory.py --mod yoda,kylo                   # several mods
#   python3 -I inventory.py --markdown > mods.md              # the ledger's mod table
#   python3 -I inventory.py --json > mods.json                # everything, machine readable
#   python3 -I inventory.py --test-cfg mp-bots --wait-scale 0.3 > bots.cfg   # a run_test.sh cfg
#   python3 -I inventory.py --test-cfg sp-npcs --mod T_Yoda --shots > yoda.cfg
#   python3 -I inventory.py --all-variants                    # ignore the skips in player_mods.conf
#   python3 -I inventory.py --mod yoda --debug                # print the equivalent shell commands only

import argparse
import fnmatch
import json
import os
import shlex
import sys
import zipfile
import zlib

# ---------------------------------------------------------------- colored prints

def _enable_windows_ansi():
	if os.name != "nt":
		return
	try:
		import ctypes
		kernel32 = ctypes.windll.kernel32
		handle = kernel32.GetStdHandle(-11)  # STD_OUTPUT_HANDLE
		mode = ctypes.c_uint32()
		if kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
			kernel32.SetConsoleMode(handle, mode.value | 0x0004)  # ENABLE_VIRTUAL_TERMINAL_PROCESSING
	except Exception:
		pass

_enable_windows_ansi()
USE_COLOR = sys.stdout.isatty()

def _c(code, text):
	return f"\033[{code}m{text}\033[0m" if USE_COLOR else text

def print_header(text):  print(_c("1;36", text))
def print_info(text):    print(_c("37", text))
def print_ok(text):      print(_c("32", text))
def print_warn(text):    print(_c("33", text))
def print_err(text):     print(_c("31", text), file=sys.stderr)
def print_key(key, val): print(f"  {_c('1;34', key + ':')} {val}")

# ---------------------------------------------------------------- constants

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONF_FILE = os.path.join(SCRIPT_DIR, "player_mods.conf")
DEFAULT_PLAYERS_SUBDIR = os.path.join("Downloads", "star_wars_ja_mods", "players")
DEFAULT_GAME_DIR_LINUX = os.path.join(".local", "share", "openjk", "JediAcademy")
INSTALL_SUBDIR = "JediAcademy"  # OpenJK's JKAInstallDir under CMAKE_INSTALL_PREFIX
BASE_DIR = "base"
STOCK_PAK_PATTERN = "assets*.pk3"
PK3_EXT = ".pk3"
TEXT_ENCODING = "latin-1"  # JA's text files are 8-bit; latin-1 never fails to decode
README_EXTS = (".txt", ".rtf", ".doc", ".md", ".pdf")
IMAGE_EXTS = (".jpg", ".jpeg", ".png", ".bmp", ".gif", ".tga", ".webp")

PLAYERS_PREFIX = "models/players/"
NPC_PREFIX = "ext_data/npcs/"
SABER_PREFIX = "ext_data/sabers/"
BOT_PREFIX = "scripts/"
JKB_PREFIX = "botfiles/"
STRINGS_PREFIX = "strings/"
UI_PREFIX = "ui/"
NPC_EXT, SABER_EXT, BOT_EXT, JKB_EXT = ".npc", ".sab", ".bot", ".jkb"
GLA_EXT, GLM_EXT, SKIN_EXT = ".gla", ".glm", ".skin"
SKIN_PREFIX = "model_"
ICON_PREFIX = "icon_"
PLAYERCHOICE_FILE = "playerchoice.txt"
SOUND_CFGS = ("sounds.cfg", "animsounds.cfg", "animevents.cfg", "animation.cfg")
NPC_SIZE_KEYS = ("scale", "height", "crouchheight", "width")
NPC_SHOWN_KEYS = ("playermodel", "customskin", "saber", "saber2") + NPC_SIZE_KEYS

# ---------------------------------------------------------------- the conf shared with the install scripts

def read_conf(path):
	"""player_mods.conf: `<keyword> <mod dir>/<file>` per line, # comments."""
	conf = {"skip": [], "extra": [], "ignore": []}
	if not os.path.isfile(path):
		return conf
	with open(path, encoding="utf-8") as f:
		for line in f:
			line = line.strip()
			if not line or line.startswith("#"):
				continue
			parts = line.split(None, 1)
			if len(parts) == 2 and parts[0].lower() in conf:
				conf[parts[0].lower()].append(parts[1].strip().replace("\\", "/"))
	return conf

def conf_has(entries, rel):
	rel = rel.replace("\\", "/").lower()
	return any(e.lower() == rel for e in entries)

# ---------------------------------------------------------------- the engine's pk3 order

def fs_path_cmp_key(name):
	"""Sort key matching FS_PathCmp (code/ and codemp/ qcommon/files.cpp): ASCII, a-z folded to
	upper case, '\\' and ':' as '/'. Pk3s are added in this order and the last one wins."""
	out = []
	for ch in name:
		if "a" <= ch <= "z":
			ch = chr(ord(ch) - 32)
		elif ch in "\\:":
			ch = "/"
		out.append(ord(ch))
	return out

# ---------------------------------------------------------------- text parsing (npc / sab / bot)

def tokenize(text):
	"""Tokens with line numbers: braces alone, quoted strings, // and /* */ comments dropped."""
	tokens, i, line, n = [], 0, 1, len(text)
	while i < n:
		ch = text[i]
		if ch == "\n":
			line += 1
			i += 1
		elif ch.isspace():
			i += 1
		elif text.startswith("//", i):
			while i < n and text[i] != "\n":
				i += 1
		elif text.startswith("/*", i):
			end = text.find("*/", i + 2)
			end = n if end < 0 else end + 2
			line += text.count("\n", i, end)
			i = end
		elif ch in "{}":
			tokens.append((ch, line))
			i += 1
		elif ch == '"':
			end = text.find('"', i + 1)
			end = n if end < 0 else end
			tokens.append((text[i + 1:end], line))
			line += text.count("\n", i, end)
			i = end + 1
		else:
			start = i
			while i < n and not text[i].isspace() and text[i] not in '{}"':
				if text.startswith("//", i):
					break
				i += 1
			tokens.append((text[start:i], line))
	return tokens

def parse_blocks(text):
	"""Top-level `name { key value ... }` blocks (name may be absent, as in .bot files).
	Returns [(name or None, {key_lower: value})]; a key's value is the rest of its line."""
	blocks, toks, i = [], tokenize(text), 0
	pending_name = None
	while i < len(toks):
		tok, _ = toks[i]
		if tok == "{":
			keys, depth, i = {}, 1, i + 1
			cur_line, cur = None, []
			while i < len(toks) and depth > 0:
				t, ln = toks[i]
				if t == "{":
					depth += 1
				elif t == "}":
					depth -= 1
				elif depth == 1:
					if ln != cur_line:
						if cur:
							keys.setdefault(cur[0].lower(), " ".join(cur[1:]))
						cur_line, cur = ln, []
					cur.append(t)
				i += 1
			if cur:
				keys.setdefault(cur[0].lower(), " ".join(cur[1:]))
			blocks.append((pending_name, keys))
			pending_name = None
		elif tok == "}":
			i += 1
		else:
			pending_name = tok
			i += 1
	return blocks

# ---------------------------------------------------------------- reading one pk3

class Pk3:
	def __init__(self, mod, path):
		self.mod = mod
		self.path = path
		self.name = os.path.basename(path)
		self.files = {}       # lower-case name -> (original name, crc, size)
		self.duplicates = []  # names listed more than once in the zip
		self.error = None
		self.npcs, self.sabers, self.bots = [], [], []
		try:
			with zipfile.ZipFile(path) as z:
				seen = set()
				for info in z.infolist():
					if info.is_dir():
						continue
					low = info.filename.replace("\\", "/").lower()
					if low in seen:
						self.duplicates.append(info.filename)
						continue
					seen.add(low)
					self.files[low] = (info.filename, info.CRC, info.file_size)
				self._parse_text(z)
		except (zipfile.BadZipFile, OSError) as e:
			self.error = str(e)

	def _read_text(self, z, low):
		return z.read(self.files[low][0]).decode(TEXT_ENCODING)

	def _parse_text(self, z):
		for low in sorted(self.files):
			if low.startswith(NPC_PREFIX) and low.endswith(NPC_EXT):
				for name, keys in parse_blocks(self._read_text(z, low)):
					shown = {k: keys[k] for k in NPC_SHOWN_KEYS if k in keys}
					self.npcs.append({"name": name, "file": low, **shown})
			elif low.startswith(SABER_PREFIX) and low.endswith(SABER_EXT):
				for name, keys in parse_blocks(self._read_text(z, low)):
					self.sabers.append({"name": name, "file": low, "model": keys.get("sabermodel", "")})
			elif low.startswith(BOT_PREFIX) and low.endswith(BOT_EXT):
				for _, keys in parse_blocks(self._read_text(z, low)):
					if "name" in keys:
						self.bots.append({"name": keys["name"], "model": keys.get("model", ""),
							"personality": keys.get("personality", ""), "file": low})

	def model_dirs(self):
		dirs = set()
		for low in self.files:
			if low.startswith(PLAYERS_PREFIX):
				rest = low[len(PLAYERS_PREFIX):]
				if "/" in rest:
					dirs.add(rest.split("/", 1)[0])
		return sorted(dirs)

	def in_model_dir(self, model, pred):
		pre = PLAYERS_PREFIX + model + "/"
		return sorted(low[len(pre):] for low in self.files if low.startswith(pre) and pred(low[len(pre):]))

# ---------------------------------------------------------------- one mod

class Mod:
	def __init__(self, players_dir, name, conf, all_variants):
		self.name = name
		self.dir = os.path.join(players_dir, name)
		self.pk3s, self.skipped, self.readmes, self.extras, self.loose_dirs, self.other = [], [], [], [], [], []
		for root, dirs, files in os.walk(self.dir):
			dirs.sort()
			rel_root = os.path.relpath(root, self.dir).replace("\\", "/")
			rel_root = "" if rel_root == "." else rel_root + "/"
			# a dir holding loose game data (models/, ext_data/ ...) is an extracted copy
			if rel_root and any(d.lower() in ("models", "ext_data", "scripts", "shaders", "sound") for d in dirs):
				self.loose_dirs.append(rel_root.rstrip("/"))
				dirs[:] = []
				continue
			for f in sorted(files):
				rel = rel_root + f
				full = os.path.join(root, f)
				low = f.lower()
				if low.endswith(PK3_EXT):
					if not all_variants and conf_has(conf["skip"], f"{name}/{rel}"):
						self.skipped.append(rel)
					else:
						self.pk3s.append(Pk3(self, full))
				elif low.endswith(README_EXTS):
					self.readmes.append(rel)
				elif low.endswith(IMAGE_EXTS):
					pass
				elif conf_has(conf["extra"], f"{name}/{rel}"):
					self.extras.append(rel)
				else:
					self.other.append(rel)
		self.all_pk3s = list(self.pk3s)
		if self.skipped:
			self.all_pk3s += [Pk3(self, os.path.join(self.dir, rel)) for rel in self.skipped]

	def alternatives(self):
		"""Groups of this mod's pk3s (installed or skipped) that ship the same model dir."""
		by_model = {}
		for p in self.all_pk3s:
			for m in p.model_dirs():
				by_model.setdefault(m, set()).add(p.name)
		groups = {tuple(sorted(v)) for v in by_model.values() if len(v) > 1}
		return sorted(groups)

	def loose_copy_check(self):
		"""For each extracted copy dir: identical to which pk3 (same names, sizes and CRCs)?"""
		results = []
		for d in self.loose_dirs:
			base = os.path.join(self.dir, d)
			loose = {}
			for root, _, files in os.walk(base):
				for f in files:
					full = os.path.join(root, f)
					rel = os.path.relpath(full, base).replace("\\", "/").lower()
					with open(full, "rb") as fh:
						data = fh.read()
					loose[rel] = (zlib.crc32(data) & 0xFFFFFFFF, len(data))
			match, renamed = None, []
			for p in self.all_pk3s:
				zipped = {k: (v[1], v[2]) for k, v in p.files.items()}
				if zipped == loose:
					match = p.name
				elif sorted(zipped.values()) == sorted(loose.values()):
					# same contents, some names differ: list them
					by_data = {v: k for k, v in loose.items()}
					renamed = [f"{k} -> {by_data[v]}" for k, v in sorted(zipped.items()) if loose.get(k) != v]
					match = p.name
			results.append((d, len(loose), match, renamed))
		return results

# ---------------------------------------------------------------- defaults per PC

def home_dir():
	return os.environ.get("USERPROFILE") if os.name == "nt" else os.path.expanduser("~")

def default_players_dir():
	return os.path.join(home_dir() or "", DEFAULT_PLAYERS_SUBDIR)

def default_game_dir():
	cache = os.path.join(SCRIPT_DIR, "..", "..", "build", "CMakeCache.txt")
	if os.path.isfile(cache):
		with open(cache, encoding="utf-8", errors="replace") as f:
			for line in f:
				if line.startswith("CMAKE_INSTALL_PREFIX:"):
					cand = os.path.join(line.split("=", 1)[1].strip(), INSTALL_SUBDIR)
					if os.path.isdir(os.path.join(cand, BASE_DIR)):
						return cand
	return os.path.join(os.path.expanduser("~"), DEFAULT_GAME_DIR_LINUX)

class Stock:
	"""The retail assets: file names, player model dirs, saber and npc names."""
	def __init__(self, game_dir):
		self.files, self.models, self.sabers, self.npcs, self.paks = set(), set(), set(), set(), []
		base = os.path.join(game_dir, BASE_DIR)
		if not os.path.isdir(base):
			return
		self.paks = sorted(f for f in os.listdir(base) if fnmatch.fnmatch(f.lower(), STOCK_PAK_PATTERN))
		for f in self.paks:
			try:
				with zipfile.ZipFile(os.path.join(base, f)) as z:
					for n in z.namelist():
						if n.endswith("/"):
							continue
						low = n.replace("\\", "/").lower()
						self.files.add(low)
						if low.startswith(PLAYERS_PREFIX) and low.count("/") >= 3:
							self.models.add(low.split("/")[2])
						elif low.startswith(SABER_PREFIX) and low.endswith(SABER_EXT):
							self.sabers.update((b or "").lower() for b, _ in parse_blocks(z.read(n).decode(TEXT_ENCODING)))
						elif low.startswith(NPC_PREFIX) and low.endswith(NPC_EXT):
							self.npcs.update((b or "").lower() for b, _ in parse_blocks(z.read(n).decode(TEXT_ENCODING)))
			except (zipfile.BadZipFile, OSError) as e:
				print_warn(f"cannot read {f}: {e}")

def cross_checks(mods, stock):
	"""Name clashes and dangling references between the installed mods and the stock assets."""
	notes = {m.name: [] for m in mods}
	models = set(stock.models)
	sabers = set(stock.sabers)
	npc_owner, bot_owner = {}, {}
	for m in mods:
		for p in m.pk3s:
			models.update(p.model_dirs())
			sabers.update((sb["name"] or "").lower() for sb in p.sabers)
	for m in mods:
		s = mod_summary(m)
		for n in s["npcs"]:
			key = (n["name"] or "").lower()
			npc_owner.setdefault(key, []).append((m.name, n["file"]))
			pm = n.get("playermodel", "").lower()
			if pm and pm not in models:
				notes[m.name].append(f"npc {n['name']}: playerModel '{pm}' is in no installed mod or stock pk3")
			for k in ("saber", "saber2"):
				sb = n.get(k, "").lower()
				if sb and sb not in sabers:
					notes[m.name].append(f"npc {n['name']}: {k} '{sb}' is defined in no installed .sab")
			if key in stock.npcs:
				notes[m.name].append(f"npc {n['name']}: same name as a stock npc ({n['file']})")
		for b in s["bots"]:
			bot_owner.setdefault(b["name"].lower(), []).append((m.name, b["file"]))
			md = b["model"].split("/", 1)[0].lower()
			if md and md not in models:
				notes[m.name].append(f"bot {b['name']}: model '{b['model']}' is in no installed mod or stock pk3")
	for kind, owners in (("npc", npc_owner), ("bot", bot_owner)):
		for name, where in sorted(owners.items()):
			distinct = sorted(set(where))
			if len(distinct) > 1:
				for mod in sorted({w[0] for w in distinct}):
					others = ", ".join(f"{w[0]}:{w[1]}" for w in distinct if w[0] != mod) or "itself"
					notes[mod].append(f"{kind} name '{name}' also defined in {others}")
	return notes

# ---------------------------------------------------------------- analysis

def analyse(mods, stock):
	"""Per mod: overrides of stock files and files shared with other mods (with the winner)."""
	owners = {}  # file -> [pk3]
	for m in mods:
		for p in m.pk3s:
			for low in p.files:
				owners.setdefault(low, []).append(p)
	report = {}
	for m in mods:
		overrides = {}
		shared = {}
		for p in m.pk3s:
			for low in p.files:
				if low in stock:
					overrides.setdefault(p.name, []).append(low)
				others = [o for o in owners[low] if o.mod is not m]
				if others:
					everyone = sorted(owners[low], key=lambda o: fs_path_cmp_key(o.name))
					winner = everyone[-1]
					key = tuple(sorted({o.mod.name for o in others}))
					entry = shared.setdefault(key, {"files": 0, "wins": 0, "loses_to": set(), "examples": []})
					entry["files"] += 1
					if winner.mod is m:
						entry["wins"] += 1
					else:
						entry["loses_to"].add(f"{winner.mod.name}/{winner.name}")
					if len(entry["examples"]) < 3:
						entry["examples"].append(low)
		report[m.name] = {"overrides": overrides, "shared": shared}
	return report

def mod_summary(m):
	models = {}
	gla, sp_menu, ui_menus, strings = [], [], [], []
	for p in m.pk3s:
		for md in p.model_dirs():
			e = models.setdefault(md, {"skins": set(), "icons": set(), "glm": False, "cfgs": set(), "pk3s": set()})
			e["pk3s"].add(p.name)
			e["skins"].update(s[len(SKIN_PREFIX):-len(SKIN_EXT)] for s in p.in_model_dir(md, lambda r: r.startswith(SKIN_PREFIX) and r.endswith(SKIN_EXT)))
			e["icons"].update(s for s in p.in_model_dir(md, lambda r: r.startswith(ICON_PREFIX)))
			e["glm"] = e["glm"] or bool(p.in_model_dir(md, lambda r: r.endswith(GLM_EXT)))
			e["cfgs"].update(p.in_model_dir(md, lambda r: r in SOUND_CFGS))
			if p.in_model_dir(md, lambda r: r == PLAYERCHOICE_FILE):
				sp_menu.append(f"{PLAYERS_PREFIX}{md}/{PLAYERCHOICE_FILE}")
		for low in p.files:
			if low.endswith(GLA_EXT):
				gla.append(low)
			elif low.startswith(STRINGS_PREFIX):
				strings.append(f"{low} ({p.name})")
			elif low.startswith(UI_PREFIX):
				ui_menus.append(low)
	jkbs = sorted({low for p in m.pk3s for low in p.files if low.startswith(JKB_PREFIX) and low.endswith(JKB_EXT)})
	return {
		"models": models, "gla": sorted(gla), "sp_menu": sorted(set(sp_menu)), "ui": sorted(set(ui_menus)),
		"strings": sorted(strings), "jkb": jkbs,
		"npcs": [n for p in m.pk3s for n in p.npcs], "sabers": [s for p in m.pk3s for s in p.sabers],
		"bots": [b for p in m.pk3s for b in p.bots],
	}

def features(s):
	"""What the files provide: MP menu icons, MP bots, npcs (SP and MP), SP menu, skeleton."""
	out = []
	if any(e["icons"] for e in s["models"].values()):
		out.append("MP menu")
	if s["bots"]:
		out.append("bots")
	if s["npcs"]:
		out.append("npcs")
	if s["sabers"]:
		out.append("sabers")
	if s["sp_menu"]:
		out.append("SP menu")
	if s["strings"]:
		out.append("MENUS.str")
	if s["gla"]:
		out.append("gla")
	return out

# ---------------------------------------------------------------- output

def print_text(mods, report, stock_paks, players_dir, game_dir):
	print_header(f"players dir: {players_dir}")
	print_header(f"game dir:    {game_dir} (stock: {', '.join(stock_paks) or 'none found'})")
	total = sum(len(m.pk3s) for m in mods)
	for m in mods:
		s = mod_summary(m)
		r = report[m.name]
		print()
		print_header(f"== {m.name}  [{', '.join(features(s)) or '-'}]")
		for p in m.pk3s:
			extra = f", {len(p.duplicates)} duplicate entries" if p.duplicates else ""
			if p.error:
				print_err(f"  pk3 {p.name}: unreadable: {p.error}")
			else:
				print_key("pk3", f"{p.name} ({len(p.files)} files{extra})")
		for rel in m.skipped:
			print_key("skipped (player_mods.conf)", rel)
		for g in m.alternatives():
			print_warn(f"  alternatives of the same model: {', '.join(g)}")
		for md, e in sorted(s["models"].items()):
			bits = [f"skins {','.join(sorted(e['skins'])) or '-'}", f"icons {len(e['icons'])}"]
			if not e["glm"]:
				bits.append("no glm (skins / cfgs on another model)")
			if e["cfgs"]:
				bits.append(" ".join(sorted(e["cfgs"])))
			print_key(f"model {md}", "; ".join(bits))
		for n in s["npcs"]:
			keys = " ".join(f"{k}={n[k]}" for k in NPC_SHOWN_KEYS if k in n)
			print_key(f"npc {n['name']}", keys)
		for b in s["bots"]:
			print_key(f"bot {b['name']}", f"model={b['model']} personality={b['personality']}")
		if s["jkb"]:
			print_key("jkb", ", ".join(s["jkb"]))
		for sb in s["sabers"]:
			print_key(f"saber {sb['name']}", sb["model"])
		if s["gla"]:
			print_warn(f"  custom skeleton: {', '.join(s['gla'])}")
		if s["sp_menu"] or s["strings"] or s["ui"]:
			print_key("SP / menu files", ", ".join(s["sp_menu"] + s["strings"] + s["ui"]))
		for pk3, files in sorted(r["overrides"].items()):
			print_warn(f"  overrides {len(files)} stock file(s) in {pk3}: {', '.join(files[:4])}{' ...' if len(files) > 4 else ''}")
		for others, e in sorted(r["shared"].items()):
			state = "wins all" if e["wins"] == e["files"] else f"wins {e['wins']}, loses to {', '.join(sorted(e['loses_to']))}"
			print_warn(f"  shares {e['files']} file(s) with {', '.join(others)} ({state}), e.g. {', '.join(e['examples'])}")
		for note in r["checks"]:
			print_warn(f"  check: {note}")
		for d, count, match, renamed in m.loose_copy_check():
			if match and renamed:
				print_ok(f"  loose copy '{d}' ({count} files) has the contents of {match}, renamed: {', '.join(renamed)}")
			elif match:
				print_ok(f"  loose copy '{d}' ({count} files) is identical to {match}")
			else:
				print_warn(f"  loose copy '{d}' ({count} files) matches no pk3")
		for rel in m.extras:
			print_key("extra file for base/", rel)
		for rel in m.other:
			print_warn(f"  unclassified file: {rel}")
		if m.readmes:
			print_key("readme", ", ".join(m.readmes))
	print()
	print_ok(f"{len(mods)} mods, {total} pk3s to install")

def md_cell(items):
	return ", ".join(items).replace("|", "\\|") or "-"

def print_markdown(mods, report):
	print("| Mod | pk3 installed | Models (skins) | NPCs (scale) | Bots | Sabers | Provides | Overrides | Shared with |")
	print("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for m in mods:
		s = mod_summary(m)
		r = report[m.name]
		pk3 = [p.name for p in m.pk3s] + [f"~~{rel}~~" for rel in m.skipped]
		models = [f"{md} ({','.join(sorted(e['skins'])) or 'no skin'})" for md, e in sorted(s["models"].items())]
		npcs = [n["name"] + (f" ({n['scale']})" if "scale" in n else "") for n in s["npcs"]]
		bots = [b["name"] for b in s["bots"]]
		sabers = [sb["name"] for sb in s["sabers"]]
		files = features(s)
		overrides = [f"{pk}: {len(f)}" for pk, f in sorted(r["overrides"].items())]
		shared = [f"{', '.join(o)} ({e['files']}, {'wins' if e['wins'] == e['files'] else 'loses' if e['wins'] == 0 else 'mixed'})" for o, e in sorted(r["shared"].items())]
		print(f"| {m.name} | {md_cell(pk3)} | {md_cell(models)} | {md_cell(npcs)} | {md_cell(bots)} | {md_cell(sabers)} | {md_cell(files)} | {md_cell(overrides)} | {md_cell(shared)} |")

def print_json(mods, report):
	out = []
	for m in mods:
		s = mod_summary(m)
		s["models"] = {k: {kk: sorted(vv) if isinstance(vv, set) else vv for kk, vv in v.items()} for k, v in s["models"].items()}
		r = report[m.name]
		out.append({
			"mod": m.name, "pk3s": [p.name for p in m.pk3s], "skipped": m.skipped, "extras": m.extras,
			"alternatives": m.alternatives(), "duplicates": {p.name: len(p.duplicates) for p in m.pk3s if p.duplicates},
			"features": features(s), **s, "overrides": r["overrides"],
			"shared": [{"with": list(o), "files": e["files"], "wins": e["wins"], "loses_to": sorted(e["loses_to"]),
				"examples": e["examples"]} for o, e in sorted(r["shared"].items())],
			"checks": r["checks"],
			"loose_copies": [{"dir": d, "files": c, "contents_of": mt, "renamed": rn} for d, c, mt, rn in m.loose_copy_check()],
			"readmes": m.readmes,
		})
	print(json.dumps(out, indent=1))

# ---------------------------------------------------------------- test cfgs for run_test.sh

TEST_CFG_KINDS = ("mp-bots", "mp-models", "mp-npcs", "sp-npcs")
TEST_MP_MAP, TEST_SP_MAP = "mp/ffa1", "t1_surprise"
TEST_MP_CLIENT_MAP = "mp/duel1"   # open floor in front of the spawn: the model faces the camera
TEST_CAMERA = ["set cg_thirdPerson 1", "set cg_thirdPersonAngle 180", "set cg_thirdPersonRange 110", "set con_notifytime 0"]
TEST_SP_RELOAD = 20     # SP checks per map load
TEST_NPC_CAMERA = ["set cg_thirdPersonAngle 0", "set cg_thirdPersonRange 160"]
TEST_MP_NPC_ANGLE = "set cg_thirdPersonAngle 90"  # MP npcs: from the side, the player does not hide them
TEST_SP_SKIP = "exitview"  # SP: skips the map's opening cinematic (Svcmd_ExitView_f)
TEST_MP_JOIN = ["team free", "togglemenu"]  # leave spectator; togglemenu sends Escape (closes the join menu)
TEST_BATCH = 6          # bots alive at once
TEST_MODEL_WAIT = 330   # frames per model change (60 fps): each sends more than one userinfo and the
                        # server takes at most 3 per 6 s (codemp/server/sv_client.cpp INFO_CHANGE_MAX_COUNT)
TEST_MARK = "echo @@"   # log marker before each check: "@@ <kind> <mod>: <what>"

def shot_name(kind, i):
	"""screenshots/<name>.jpg of check i (`screenshot <name>` writes a JPEG in OpenJK)."""
	return f"{kind.replace('-', '_')}_{i:03d}"

def test_cfg(kind, mods, shots, wait_scale):
	"""A cfg for run_test.sh: one marked check per bot / model skin / npc of the given mods."""
	w = lambda frames: f"wait {max(1, int(frames * wait_scale))}"
	out = [f"// generated by inventory.py --test-cfg {kind}"] + TEST_CAMERA
	if kind.endswith("npcs"):
		out += TEST_NPC_CAMERA  # npcs spawn in front of the player: look past the player instead
	items = []
	for m in mods:
		s = mod_summary(m)
		if kind == "mp-bots":
			items += [(m.name, b["name"]) for b in s["bots"]]
		elif kind == "mp-models":
			for md, e in sorted(s["models"].items()):
				if e["glm"]:
					items += [(m.name, f"{md}/{sk}") for sk in sorted(e["skins"]) or ["default"]]
		else:
			items += [(m.name, n["name"]) for n in s["npcs"] if n["name"]]
	seen = set()
	items = [i for i in items if not (i[1].lower() in seen or seen.add(i[1].lower()))]
	if kind == "mp-bots":
		out += ["set sv_maxclients 16", f"map {TEST_MP_MAP}", w(200)]
		for i, (mod, name) in enumerate(items):
			out += [f'{TEST_MARK} bot {mod}: {name}', f'addbot "{name}" 1', w(40)]
			if i % TEST_BATCH == TEST_BATCH - 1 or i == len(items) - 1:
				out += [w(200), "kick allbots", w(40)]
	elif kind == "mp-models":
		out += [f"devmap {TEST_MP_CLIENT_MAP}", w(600), TEST_MP_JOIN[0], w(120), TEST_MP_JOIN[1], w(300)]
		for i, (mod, name) in enumerate(items):
			out += [f"{TEST_MARK} model {mod}: {name} [{shot_name(kind, i)}]", f"model {name}", w(TEST_MODEL_WAIT)]
			if shots:
				out += [f"screenshot {shot_name(kind, i)}", w(20)]
	else:
		mp = kind == "mp-npcs"
		for i, (mod, name) in enumerate(items):
			if i == 0 or (not mp and i % TEST_SP_RELOAD == 0):
				# SP: a fresh map every TEST_SP_RELOAD checks keeps the 64 skin configstrings of a
				# level from overflowing (G_FindConfigstringIndex)
				out += [f"devmap {TEST_MP_CLIENT_MAP if mp else TEST_SP_MAP}", w(600)]
				out += [TEST_MP_JOIN[0], w(120), TEST_MP_JOIN[1], w(300), "notarget"] if mp else [TEST_SP_SKIP, w(400), "helpusobi 1", "notarget"]
			out += [TEST_MP_NPC_ANGLE if mp else TEST_NPC_CAMERA[0], f"{TEST_MARK} npc {mod}: {name} [{shot_name(kind, i)}]", f"npc spawn {name}", w(100)]
			if shots:
				out += [f"screenshot {shot_name(kind, i)}", w(20)]
			out += ["npc kill all", w(60)]  # one at a time: piled-up npcs fight and hide each other
			if not mp:
				out += [TEST_CAMERA[1], f"{TEST_MARK} playermodel {mod}: {name} [{shot_name('pm', i)}]", f"playermodel {name}", w(100)]
				if shots:
					out += [f"screenshot {shot_name('pm', i)}", w(20)]
	out += [f"{TEST_MARK} end", w(60), "quit"]
	return "\n".join(out) + "\n"

# ---------------------------------------------------------------- main

def debug_command(args, mods):
	"""The shell equivalent of the file side of this run: each selected pk3's file list and the
	stock files it replaces. The .npc / .bot / .sab parsing and the cross checks have none."""
	invocation = " ".join(sys.argv)
	pk3s = [p.path for m in mods for p in m.pk3s]
	stock_glob = os.path.join(args.game, BASE_DIR, STOCK_PAK_PATTERN)
	if os.name == "nt":
		q = lambda x: "'" + x.replace("'", "''") + "'"
		lines = [f"# {invocation}",
			"# file lists and stock overrides only; the npc / bot / sab parsing has no shell equivalent",
			"Add-Type -AssemblyName System.IO.Compression.FileSystem",
			"function ZipNames($p) { $z = [IO.Compression.ZipFile]::OpenRead($p); try { $z.Entries | ? { -not $_.FullName.EndsWith('/') } | % { $_.FullName.Replace('\\', '/').ToLower() } } finally { $z.Dispose() } }",
			f"$stock = @{{}}; Get-ChildItem {q(stock_glob)} | % {{ ZipNames $_.FullName | % {{ $stock[$_] = 1 }} }}",
			f"foreach ($pk3 in @({', '.join(q(x) for x in pk3s)})) {{",
			"\t\"== $pk3\"; $names = ZipNames $pk3 | Sort-Object -Unique; $names",
			"\t\"-- replaces stock:\"; $names | ? { $stock.ContainsKey($_) }",
			"}"]
	else:
		q = shlex.quote
		lines = [f"# {invocation}",
			"# file lists and stock overrides only; the npc / bot / sab parsing has no shell equivalent",
			f"stock=$(mktemp); for p in {q(os.path.dirname(stock_glob))}/{STOCK_PAK_PATTERN}; do zipinfo -1 \"$p\"; done | grep -v '/$' | tr '[:upper:]' '[:lower:]' | sort -u > \"$stock\"",
			"for pk3 in \\"] + [f"\t{q(x)} \\" for x in pk3s] + ["; do",
			"\techo \"== $pk3\"; zipinfo -1 \"$pk3\" | grep -v '/$' | sort -fu",
			"\techo \"-- replaces stock:\"; zipinfo -1 \"$pk3\" | grep -v '/$' | tr '[:upper:]' '[:lower:]' | sort -u | comm -12 - \"$stock\"",
			"done; rm -f \"$stock\""]
	return "\n".join(lines)

def main():
	ap = argparse.ArgumentParser(description="Inventory of Jedi Academy player model mods (pk3s read as zips only).")
	ap.add_argument("players_pos", nargs="?", metavar="PLAYERS_DIR", help="players dir (one dir per mod)")
	ap.add_argument("--players", "-p", help=f"players dir (default ~/{DEFAULT_PLAYERS_SUBDIR})")
	ap.add_argument("--game", "-g", help="install game dir with base/assets*.pk3 (default from build/CMakeCache.txt)")
	ap.add_argument("--mod", "-m", help="only mods whose dir name contains this; comma-separated for several (case-insensitive unless -c)")
	ap.add_argument("--case-sensitive", "-c", action="store_true", help="case-sensitive --mod match")
	ap.add_argument("--all-variants", action="store_true", help="also read the pk3s player_mods.conf skips")
	ap.add_argument("--markdown", action="store_true", help="print the ledger's mod table")
	ap.add_argument("--json", action="store_true", help="print everything as JSON")
	ap.add_argument("--test-cfg", choices=TEST_CFG_KINDS, help="print a run_test.sh cfg checking every bot / model skin / npc")
	ap.add_argument("--shots", action="store_true", help="--test-cfg: a screenshot after each check")
	ap.add_argument("--wait-scale", type=float, default=1.0, help="--test-cfg: scale every wait (dedicated runs at sv_fps)")
	ap.add_argument("--no-color", action="store_true", help="no ANSI colors")
	ap.add_argument("--debug", "-d", action="store_true", help="print the equivalent shell commands (zip listings) instead of running")
	args = ap.parse_args()

	global USE_COLOR
	if args.no_color or args.markdown or args.json or args.test_cfg:
		USE_COLOR = False
	args.players = os.path.abspath(os.path.expanduser(args.players or args.players_pos or default_players_dir()))
	args.game = os.path.abspath(os.path.expanduser(args.game or default_game_dir()))
	if not os.path.isdir(args.players):
		print_err(f"players dir not found: {args.players}")
		return 1

	conf = read_conf(CONF_FILE)
	names = sorted((d for d in os.listdir(args.players) if os.path.isdir(os.path.join(args.players, d))), key=str.lower)
	all_mods = [Mod(args.players, n, conf, args.all_variants) for n in names]
	if args.mod:
		wants = [w for w in (args.mod if args.case_sensitive else args.mod.lower()).split(",") if w]
		shown = [m for m in all_mods if any(w in (m.name if args.case_sensitive else m.name.lower()) for w in wants)]
	else:
		shown = all_mods
	if args.debug:
		print(debug_command(args, shown))
		return 0
	if args.test_cfg:
		sys.stdout.write(test_cfg(args.test_cfg, shown, args.shots, args.wait_scale))
		return 0
	stock = Stock(args.game)
	if not stock.paks:
		print_warn(f"no {STOCK_PAK_PATTERN} in {os.path.join(args.game, BASE_DIR)}: stock overrides not checked")
	report = analyse(all_mods, stock.files)  # shared files are always checked against every mod
	for name, notes in cross_checks(all_mods, stock).items():
		report[name]["checks"] = notes

	if args.json:
		print_json(shown, report)
	elif args.markdown:
		print_markdown(shown, report)
	else:
		print_text(shown, report, stock.paks, args.players, args.game)
	return 0

if __name__ == "__main__":
	sys.exit(main())
