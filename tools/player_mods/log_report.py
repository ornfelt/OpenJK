#!/usr/bin/env python3
# Groups a run_test.sh console log by its check markers ("@@ <kind> <mod>: <what> [<shot>]", written
# by the cfgs inventory.py --test-cfg makes) and prints, per check, the error lines it produced that
# a baseline log (the same cfg without mods) did not. Optionally builds labelled contact sheets of
# the checks' screenshots (ImageMagick montage) so many models can be looked at at once.
#
# Usage examples:
#   python3 -I log_report.py <home>/playermods_test/qconsole.log
#   python3 -I log_report.py --log <log> --baseline <no-mods log>
#   python3 -I log_report.py <log> --only-errors                 # skip checks without new lines
#   python3 -I log_report.py <log> --sheets <out dir>            # contact sheets, 12 shots per sheet
#   python3 -I log_report.py <log> --sheets <out dir> --crop 440x420+420+300   # only the model area
#   python3 -I log_report.py <log> --grep "g2|ghoul" -c          # own filter, case-sensitive
#   python3 -I log_report.py <log> --debug                       # print the equivalent shell commands

import argparse
import os
import re
import shlex
import subprocess
import sys

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

MARK_RE = re.compile(r"^@@ (?P<kind>\S+) (?P<mod>[^:]+): (?P<what>.*?)(?: \[(?P<shot>[^\]]+)\])?$")
TIME_RE = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} )+")  # some lines carry it twice
PROBE_RE = re.compile(r"^Can't find (.*\.(wav|jpg|png|tga|surf|ste)|models/players/[^/]*/(sounds_[^/]*\.cfg|PlayerChoice\.txt))$")  # extension / variant probes, as in run_test.sh
DEFAULT_GREP = r"couldn't|can't|cannot|warning|error|failed|not found|g2|ghoul|missing|default model|bad |exceeded|overflow|unknown"
SHOTS_SUBDIR = "screenshots"
SHOT_EXT = ".jpg"
SHEET_TILE = "6x"
SHEET_SIZE = 24
SHEET_GEOMETRY = "300x300>+2+2"

def read_lines(path):
	with open(path, encoding="latin-1") as f:
		return [TIME_RE.sub("", l.rstrip("\r\n")) for l in f]

def checks(lines):
	"""[(marker dict or None, [lines])] in log order; the lines before the first marker under None."""
	out, cur, buf = [], None, []
	for l in lines:
		m = MARK_RE.match(l)
		if m:
			out.append((cur, buf))
			cur, buf = m.groupdict(), []
		else:
			buf.append(l)
	out.append((cur, buf))
	return out

def main():
	ap = argparse.ArgumentParser(description="Per-check error lines and screenshot sheets of a run_test.sh log.")
	ap.add_argument("log_pos", nargs="?", metavar="LOG")
	ap.add_argument("--log", "-l")
	ap.add_argument("--baseline", "-b", help="log of the same cfg without mods: its lines are not reported")
	ap.add_argument("--grep", "-g", default=DEFAULT_GREP, help="error line filter (regex)")
	ap.add_argument("--case-sensitive", "-c", action="store_true")
	ap.add_argument("--only-errors", action="store_true", help="list only checks with new error lines")
	ap.add_argument("--sheets", help="write labelled contact sheets of the checks' screenshots here")
	ap.add_argument("--crop", help="--sheets: crop each shot first (ImageMagick geometry, e.g. 440x420+420+300)")
	ap.add_argument("--no-color", action="store_true")
	ap.add_argument("--debug", "-d", action="store_true", help="print the equivalent shell commands instead")
	args = ap.parse_args()
	global USE_COLOR
	if args.no_color:
		USE_COLOR = False
	log = args.log or args.log_pos
	if not log:
		ap.error("give the log")
	flags = 0 if args.case_sensitive else re.IGNORECASE
	err_re = re.compile(args.grep, flags)
	shots_dir = os.path.join(os.path.dirname(os.path.abspath(log)), SHOTS_SUBDIR)

	if args.debug:
		q = shlex.quote
		i = "" if args.case_sensitive else "i"
		print(f"# {' '.join(sys.argv)}")
		base = f" | grep -vxF -f <(sed -E 's/^([0-9-]+ [0-9:]+ )+//' {q(args.baseline)})" if args.baseline else ""
		print(f"sed -E 's/^([0-9-]+ [0-9:]+ )+//' {q(log)} | grep -vE {q(PROBE_RE.pattern)}{base} | grep -E{i} {q('^@@ |' + args.grep)}")
		if args.sheets:
			crop = f"-crop {q(args.crop)} " if args.crop else ""
			print(f"mkdir -p {q(args.sheets)} && montage {crop}-label '%t' {q(shots_dir)}/*{SHOT_EXT} -tile {SHEET_TILE} -geometry {SHEET_GEOMETRY} {q(args.sheets)}/sheet_%02d.jpg")
		return 0

	baseline = set(read_lines(args.baseline)) if args.baseline else set()
	report, shots = [], []
	for mark, body in checks(read_lines(log)):
		errs = [l for l in body if err_re.search(l) and not PROBE_RE.match(l) and l not in baseline]
		seen = set()
		errs = [l for l in errs if not (l in seen or seen.add(l))]
		report.append((mark, errs))
		if mark and mark.get("shot"):
			shots.append((mark, os.path.join(shots_dir, mark["shot"] + SHOT_EXT)))

	bad = 0
	for mark, errs in report:
		label = "(before the first check)" if mark is None else f"{mark['kind']} {mark['mod']}: {mark['what']}"
		if mark and mark["kind"] == "end":
			continue
		if errs:
			bad += 1
			print_header(label)
			for e in errs:
				print_warn(f"    {e}")
		elif not args.only_errors and mark is not None:
			print_ok(f"{label}: no new error lines")
	print(f"{len([r for r in report if r[0] and r[0]['kind'] != 'end'])} checks, {bad} with new error lines")

	if args.sheets and shots:
		os.makedirs(args.sheets, exist_ok=True)
		present = [(m, p) for m, p in shots if os.path.isfile(p)]
		missing = len(shots) - len(present)
		for n in range(0, len(present), SHEET_SIZE):
			part = present[n:n + SHEET_SIZE]
			cmd = ["montage"] + (["-crop", args.crop] if args.crop else [])
			for m, p in part:
				cmd += ["-label", f"{m['shot']} {m['what']}", p]
			out = os.path.join(args.sheets, f"sheet_{n // SHEET_SIZE:02d}.jpg")
			cmd += ["-tile", SHEET_TILE, "-geometry", SHEET_GEOMETRY, "-pointsize", "16", out]
			subprocess.run(cmd, check=True)
			print(f"sheet {out}")
		if missing:
			print_warn(f"{missing} screenshot(s) missing")
	return 0

if __name__ == "__main__":
	sys.exit(main())
