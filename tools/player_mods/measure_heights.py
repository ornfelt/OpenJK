#!/usr/bin/env python3
# Measures the height of Jedi Academy player models from their meshes, against Kyle's.
#
# For every models/players/<dir>/model.glm (the copy the engine would load: the stock assets*.pk3
# first, then the pk3s of the installed base/ dir, each in FS_PathCmp order, the last one wins) it
# reads LOD 0 and takes the base-pose height of the surfaces that are drawn: not the "*" tag
# surfaces, not the ones flagged off ("_off" names) and not the ones model_default.skin sets to
# *off. All humanoid player models share one skeleton and its animations, so the base-pose heights
# compare the models as they stand in game (step 8 of PLAYER_MODS_STATUS.md checks that with
# screenshots). The ratio to Kyle is the size at scale 1.0; with --target a table of in-universe
# heights it also proposes the modelscale.cfg factor (target height / Kyle's / ratio).
#
# The pk3s are only read as zips: nothing is extracted and nothing from them is run. Run it with
# `python3 -I`.
#
# Usage examples:
#   python3 -I measure_heights.py                                  # the mods in the OpenJK homepath's base/
#   python3 -I measure_heights.py /tmp/ojk_home/base               # an installed base/ dir, positional ...
#   python3 -I measure_heights.py --base /tmp/ojk_home/base        # ... or named
#   python3 -I measure_heights.py --all                            # stock models too
#   python3 -I measure_heights.py --model yoda,grievous            # only dirs containing these (case-insensitive)
#   python3 -I measure_heights.py --model T_Yoda -c                # case-sensitive match
#   python3 -I measure_heights.py --target heights.txt             # propose modelscale.cfg factors
#   python3 -I measure_heights.py --json > heights.json            # machine readable
#   python3 -I measure_heights.py --target heights.txt --sizes     # "<model> <percent>" lines (size_check.sh)
#   python3 -I measure_heights.py --cfg base/modelscale.cfg --sizes   # the same from a modelscale.cfg
#   python3 -I measure_heights.py --game ~/.local/share/openjk/JediAcademy --debug   # the equivalent shell commands only
#
# --target file: "<model> <height in metres>" per line, "//" comments; the "kyle" line sets Kyle's
# height (default KYLE_HEIGHT_M).

import argparse
import glob
import json
import os
import shlex
import struct
import sys
import zipfile

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
def print_ok(text):      print(_c("32", text))
def print_warn(text):    print(_c("33", text), file=sys.stderr)
def print_err(text):     print(_c("31", text), file=sys.stderr)
def print_key(key, val): print(f"  {_c('1;34', key + ':')} {val}")

# ---------------------------------------------------------------- constants

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
INSTALL_SUBDIR = "JediAcademy"          # OpenJK's JKAInstallDir under CMAKE_INSTALL_PREFIX
DEFAULT_GAME_DIR_LINUX = os.path.join(".local", "share", "openjk", "JediAcademy")
DEFAULT_HOME_LINUX = os.path.join(".local", "share", "openjk")
DEFAULT_HOME_WINDOWS = os.path.join("Documents", "My Games", "OpenJK")
BASE_DIR = "base"
STOCK_PAK_PATTERN = "assets*.pk3"
PK3_EXT = ".pk3"
TEXT_ENCODING = "latin-1"
PLAYERS_PREFIX = "models/players/"
MODEL_FILE = "model.glm"
DEFAULT_SKIN_FILE = "model_default.skin"
SKIN_OFF = "*off"
REFERENCE_MODEL = "kyle"
KYLE_HEIGHT_M = 1.80                    # Kyle Katarn's assumed height, overridable in --target

# rd-common/mdx_format.h
GLM_IDENT = b"2LGM"
GLM_VERSION = 6
GLM_HEADER_SIZE = 164                   # sizeof( mdxmHeader_t ); the hierarchy offsets follow it
GLM_OFS_COUNTS = 140                    # numBones, numLODs, ofsLODs, numSurfaces, ofsSurfHierarchy, ofsEnd
NAME_SIZE = 64                          # MAX_QPATH
SURF_FLAGS = NAME_SIZE                  # mdxmSurfHierarchy_t.flags after name[64]
G2SURFACEFLAG_OFF = 0x2
SURF_OFS_NUMVERTS = 12                  # mdxmSurface_t: ident, thisSurfaceIndex, ofsHeader, numVerts, ofsVerts
VERTEX_SIZE = 32                        # mdxmVertex_t: normal[3], vertCoords[3], weights, BoneWeightings[4]
VERTEX_COORDS = 12
TAG_PREFIX = "*"

# ---------------------------------------------------------------- defaults per PC

def home_dir():
	return os.environ.get("USERPROFILE") if os.name == "nt" else os.path.expanduser("~")

def default_game_dir():
	cache = os.path.join(SCRIPT_DIR, "..", "..", "build", "CMakeCache.txt")
	if os.path.isfile(cache):
		with open(cache, encoding="utf-8", errors="replace") as f:
			for line in f:
				if line.startswith("CMAKE_INSTALL_PREFIX:"):
					cand = os.path.join(line.split("=", 1)[1].strip(), INSTALL_SUBDIR)
					if os.path.isdir(os.path.join(cand, BASE_DIR)):
						return cand
	return os.path.join(home_dir() or "", DEFAULT_GAME_DIR_LINUX)

def default_base_dir():
	sub = DEFAULT_HOME_WINDOWS if os.name == "nt" else DEFAULT_HOME_LINUX
	return os.path.join(home_dir() or "", sub, BASE_DIR)

# ---------------------------------------------------------------- the engine's pk3 order

def fs_path_cmp_key(name):
	"""Sort key matching FS_PathCmp: ASCII, a-z folded to upper case, '\\' and ':' as '/'."""
	out = []
	for ch in name:
		if "a" <= ch <= "z":
			ch = chr(ord(ch) - 32)
		elif ch in "\\:":
			ch = "/"
		out.append(ord(ch))
	return out

def ordered_paks(stock_base, mods_base):
	"""Stock pk3s, then the installed base/'s: lowest priority first."""
	stock = sorted(glob.glob(os.path.join(stock_base, STOCK_PAK_PATTERN)), key=lambda p: fs_path_cmp_key(os.path.basename(p)))
	mods = []
	if mods_base and os.path.isdir(mods_base):
		mods = sorted((p for p in glob.glob(os.path.join(mods_base, "*")) if p.lower().endswith(PK3_EXT)),
			key=lambda p: fs_path_cmp_key(os.path.basename(p)))
	return stock, mods

def winning_files(paks):
	"""lower-case path -> (pk3, name inside it) of the copy the engine loads."""
	files = {}
	for p in paks:
		try:
			with zipfile.ZipFile(p) as z:
				for n in z.namelist():
					if not n.endswith("/"):
						files[n.replace("\\", "/").lower()] = (p, n)
		except (OSError, zipfile.BadZipFile) as e:
			print_warn(f"skipped {p}: {e}")
	return files

def read_member(where):
	pak, name = where
	with zipfile.ZipFile(pak) as z:
		return z.read(name)

# ---------------------------------------------------------------- the mesh

def skin_off_surfaces(text):
	off = set()
	for line in text.splitlines():
		parts = [x.strip() for x in line.split(",", 1)]
		if len(parts) == 2 and parts[1].lower() == SKIN_OFF:
			off.add(parts[0].lower())
	return off

def glm_height(data, off):
	"""(min z, max z, drawn surfaces, vertices) of LOD 0's drawn surfaces, or None."""
	if len(data) < GLM_HEADER_SIZE or data[:4] != GLM_IDENT or struct.unpack_from("<i", data, 4)[0] != GLM_VERSION:
		return None
	_bones, num_lods, ofs_lods, num_surfs, _ofs_hier, _end = struct.unpack_from("<6i", data, GLM_OFS_COUNTS)
	if num_lods < 1 or num_surfs < 1:
		return None
	names, flags = [], []
	for i in range(num_surfs):
		at = GLM_HEADER_SIZE + struct.unpack_from("<i", data, GLM_HEADER_SIZE + 4 * i)[0]
		names.append(data[at:at + NAME_SIZE].split(b"\0")[0].decode(TEXT_ENCODING).lower())
		flags.append(struct.unpack_from("<I", data, at + SURF_FLAGS)[0])
	lod_offsets = ofs_lods + 4  # after mdxmLOD_t.ofsEnd
	lo, hi, drawn, verts = None, None, 0, 0
	for i in range(num_surfs):
		if names[i].startswith(TAG_PREFIX) or flags[i] & G2SURFACEFLAG_OFF or names[i] in off:
			continue
		surf = lod_offsets + struct.unpack_from("<i", data, lod_offsets + 4 * i)[0]
		num_verts, ofs_verts = struct.unpack_from("<2i", data, surf + SURF_OFS_NUMVERTS)
		if num_verts <= 0:
			continue
		drawn += 1
		for v in range(num_verts):
			z = struct.unpack_from("<f", data, surf + ofs_verts + v * VERTEX_SIZE + VERTEX_COORDS + 8)[0]
			lo = z if lo is None or z < lo else lo
			hi = z if hi is None or z > hi else hi
			verts += 1
	return None if lo is None or hi is None else (lo, hi, drawn, verts)

def measure(files, model):
	glm = files.get(f"{PLAYERS_PREFIX}{model}/{MODEL_FILE}")
	if not glm:
		return None
	skin = files.get(f"{PLAYERS_PREFIX}{model}/{DEFAULT_SKIN_FILE}")
	off = skin_off_surfaces(read_member(skin).decode(TEXT_ENCODING)) if skin else set()
	got = glm_height(read_member(glm), off)
	if not got:
		return None
	lo, hi, drawn, verts = got
	return {"model": model, "pk3": os.path.basename(glm[0]), "min_z": round(lo, 2), "max_z": round(hi, 2),
		"height": round(hi - lo, 2), "surfaces": drawn, "vertices": verts}

# ---------------------------------------------------------------- --target

def read_targets(path):
	targets, kyle = {}, KYLE_HEIGHT_M
	with open(path, encoding="utf-8") as f:
		for line in f:
			line = line.split("//", 1)[0].split()
			if len(line) < 2:
				continue
			try:
				metres = float(line[1])
			except ValueError:
				print_warn(f"{path}: not a height: {' '.join(line)}")
				continue
			if line[0].lower() == REFERENCE_MODEL:
				kyle = metres
			else:
				targets[line[0].lower()] = metres
	return targets, kyle

def read_cfg_sizes(path):
	"""model (lower case) -> factor from a modelscale.cfg (pairs, // and /* */ comments)."""
	with open(path, encoding=TEXT_ENCODING) as f:
		text = f.read()
	out, i = [], 0
	while i < len(text):
		if text.startswith("/*", i):
			end = text.find("*/", i + 2)
			i = len(text) if end < 0 else end + 2
		elif text.startswith("//", i):
			end = text.find("\n", i)
			i = len(text) if end < 0 else end
		else:
			out.append(text[i])
			i += 1
	toks = "".join(out).split()
	sizes = {}
	for k in range(0, len(toks) - 1, 2):
		try:
			sizes[toks[k].lower()] = float(toks[k + 1])
		except ValueError:
			print_warn(f"{path}: not a scale: {toks[k]} {toks[k + 1]}")
	return sizes

# ---------------------------------------------------------------- main

def main():
	ap = argparse.ArgumentParser(description="Player model heights from their meshes, against Kyle's (pk3s read as zips only).")
	ap.add_argument("base_pos", nargs="?", metavar="BASE_DIR", help="installed base/ dir holding the mod pk3s")
	ap.add_argument("--base", "-b", help="installed base/ dir (default: the OpenJK homepath's base/)")
	ap.add_argument("--game", "-g", help="install game dir with base/assets*.pk3 (default from build/CMakeCache.txt)")
	ap.add_argument("--model", "-m", help="only model dirs containing this; comma-separated (case-insensitive unless -c)")
	ap.add_argument("--case-sensitive", "-c", action="store_true", help="case-sensitive --model match")
	ap.add_argument("--all", "-a", action="store_true", help="stock models too, not only the ones the installed pk3s ship")
	ap.add_argument("--target", "-t", help="file of '<model> <metres>' lines: propose modelscale.cfg factors")
	ap.add_argument("--cfg", help="a modelscale.cfg: its sizes instead of --target's (with --sizes)")
	ap.add_argument("--sizes", action="store_true", help="print only '<model> <percent>' lines (--target proposal or --cfg)")
	ap.add_argument("--json", action="store_true", help="print the results as JSON")
	ap.add_argument("--no-color", action="store_true", help="no ANSI colors")
	ap.add_argument("--debug", "-d", action="store_true", help="print the equivalent shell commands instead of running")
	args = ap.parse_args()

	global USE_COLOR
	if args.no_color or args.json or args.sizes:
		USE_COLOR = False
	game = args.game or default_game_dir()
	base = args.base or args.base_pos or default_base_dir()
	stock, mods = ordered_paks(os.path.join(game, BASE_DIR), base)

	if args.debug:
		print("# the engine's load order, lowest priority first; per model the last pk3 holding the file wins:")
		for p in stock + mods:
			print(f"unzip -l {shlex.quote(p)} '{PLAYERS_PREFIX}*/{MODEL_FILE}' '{PLAYERS_PREFIX}*/{DEFAULT_SKIN_FILE}'")
		print(f"# then per model: unzip -p <pk3> {PLAYERS_PREFIX}<model>/{MODEL_FILE} | <read LOD 0 vertex z of the drawn surfaces>")
		return 0
	if not stock:
		print_err(f"no {STOCK_PAK_PATTERN} in {os.path.join(game, BASE_DIR)} (--game <dir>)")
		return 1

	files = winning_files(stock + mods)
	mod_files = winning_files(mods)
	models = sorted({p[len(PLAYERS_PREFIX):].split("/")[0] for p in files
		if p.startswith(PLAYERS_PREFIX) and p.endswith("/" + MODEL_FILE) and p.count("/") == 3})
	if not args.all:
		shipped = {p[len(PLAYERS_PREFIX):].split("/")[0] for p in mod_files if p.startswith(PLAYERS_PREFIX)}
		models = [m for m in models if m in shipped or m == REFERENCE_MODEL]
	if args.model:
		wanted = args.model.split(",")
		match = (lambda m: any(w in m for w in wanted)) if args.case_sensitive else \
			(lambda m: any(w.lower() in m.lower() for w in wanted))
		models = [m for m in models if match(m) or m == REFERENCE_MODEL]

	ref = measure(files, REFERENCE_MODEL)
	if not ref:
		print_err(f"no {PLAYERS_PREFIX}{REFERENCE_MODEL}/{MODEL_FILE} to compare with")
		return 1
	targets, kyle_m = read_targets(args.target) if args.target else ({}, KYLE_HEIGHT_M)

	rows = []
	for m in models:
		r = measure(files, m)
		if not r:
			print_warn(f"{m}: no readable {MODEL_FILE}")
			continue
		r["ratio"] = round(r["height"] / ref["height"], 3)
		r["metres"] = round(r["ratio"] * kyle_m, 2)
		if m in targets:
			r["target_m"] = targets[m]
			r["scale"] = round(targets[m] / kyle_m / r["ratio"], 2)
		rows.append(r)

	if args.sizes:
		cfg = read_cfg_sizes(args.cfg) if args.cfg else None
		for r in rows:
			if r["model"] == REFERENCE_MODEL:
				continue
			factor = cfg.get(r["model"], 1.0) if cfg is not None else r.get("scale")
			if factor is not None:
				print(r["model"], int(factor * 100 + 0.5))
		return 0
	if args.json:
		print(json.dumps({"reference": ref, "kyle_m": kyle_m, "models": rows}, indent=1))
		return 0
	print_header(f"player model heights (LOD 0 base pose, drawn surfaces) - {REFERENCE_MODEL} = {ref['height']} units = {kyle_m} m")
	print_key("stock", os.path.join(game, BASE_DIR))
	print_key("mods", base)
	print(f"  {'model':24} {'height':>7} {'ratio':>6} {'~m':>5} {'target':>7} {'scale':>6}  pk3")
	for r in rows:
		target = f"{r['target_m']:.2f}" if "target_m" in r else "-"
		scale = f"{r['scale']:.2f}" if "scale" in r else "-"
		line = f"  {r['model']:24} {r['height']:7.2f} {r['ratio']:6.3f} {r['metres']:5.2f} {target:>7} {scale:>6}  {r['pk3']}"
		print(_c("33", line) if abs(r["ratio"] - 1) > 0.15 else line)
	print_ok(f"{len(rows)} model(s)")
	return 0

if __name__ == "__main__":
	sys.exit(main())
