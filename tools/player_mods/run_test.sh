#!/usr/bin/env bash
# Runs the fork's freshly built JA SP / MP / dedicated binaries against a throwaway homepath with
# the player mods installed, executes a cfg of test commands and scans the console log.
#
# The home gets base/ (the mods, via install_player_mods.sh --dest), bin/ (copies of the built
# engine and renderers, which load from the binary's dir) and playermods_test/ (the built game
# modules, loaded through +set fs_game playermods_test, plus the test cfg and the console log).
# The retail data comes in read only through fs_basepath. No master servers, LAN only.
#
# Usage examples:
#   dedicated MP server, bots added from a cfg (one command per line, `wait` lines allowed):
#     ./run_test.sh ded --cfg tests/bots.cfg
#   MP client, commands inline (separated by ';'), screenshots end up in <home>/playermods_test/screenshots:
#     ./run_test.sh mp --exec "devmap mp/ffa1; wait 300; model swtorrevan; wait 200; screenshotJPEG; quit"
#   SP client in a given home, kept for inspection, without (re)installing the mods:
#     ./run_test.sh sp --home /tmp/ojk_home --no-install --exec "devmap t1_surprise; wait 500; quit"
#   no mods at all (the "behaves as before" check):
#     ./run_test.sh ded --no-mods --exec "map mp/ffa1; wait 100; quit"
#   only some mods, error lines filtered case-sensitively:
#     ./run_test.sh ded --only T_Yoda,grievousvm --grep "G2|Couldn't" -c --exec "..."
#   only the error lines that a no-mods run of the same cfg did not print:
#     ./run_test.sh ded --no-mods --home /tmp/h0 --cfg tests/bots.cfg
#     ./run_test.sh ded --baseline /tmp/h0/playermods_test/qconsole.log --cfg tests/bots.cfg
#   read the mouse (not grabbed) for a menu driver such as sp_menu_check.sh:
#     ./run_test.sh sp --mouse --exec "wait 3000; quit"
#   remove the home afterwards:
#     ./run_test.sh ded --clean --exec "..."
#   print the equivalent shell commands instead of running them:
#     ./run_test.sh mp --debug --exec "devmap mp/ffa1; quit"

set -euo pipefail

# ---------------------------------------------------------------- colored prints
if [[ -t 1 ]]; then
	C_HEAD=$'\033[1;36m' C_OK=$'\033[32m' C_WARN=$'\033[33m' C_ERR=$'\033[31m' C_KEY=$'\033[1;34m' C_OFF=$'\033[0m'
else
	C_HEAD='' C_OK='' C_WARN='' C_ERR='' C_KEY='' C_OFF=''
fi
print_header() { printf '%s%s%s\n' "$C_HEAD" "$*" "$C_OFF"; }
print_ok()     { printf '%s%s%s\n' "$C_OK" "$*" "$C_OFF"; }
print_warn()   { printf '%s%s%s\n' "$C_WARN" "$*" "$C_OFF"; }
print_err()    { printf '%s%s%s\n' "$C_ERR" "$*" "$C_OFF" >&2; }
print_key()    { printf '  %s%s:%s %s\n' "$C_KEY" "$1" "$C_OFF" "$2"; }

# ---------------------------------------------------------------- constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="$REPO_DIR/build"
TEST_GAME="playermods_test"
CFG_NAME="autotest.cfg"
LOG_NAME="qconsole.log"
INSTALL_SUBDIR="JediAcademy"
ARCH="x86_64"
DEFAULT_TIMEOUT=300
# the engine probes other extensions (sound .wav before .mp3, image .tga/.jpg/.png, optional .surf,
# the .ste twin of each .str string file, a skin's sounds_<skin>.cfg before sounds.cfg, every
# model dir's PlayerChoice.txt in the MP UI)
PROBE_RE="^Can't find (.*\\.(wav|jpg|png|tga|surf|ste)|models/players/[^/]*/(sounds_[^/]*\\.cfg|PlayerChoice\\.txt))$"
DEFAULT_GREP="couldn't|can't|cannot|warning|error|failed|not found|g2|ghoul|missing|default model|bad |exceeded|overflow"
# com_maxfps pins `wait` to 60 per second: the server takes at most 3 userinfo changes per 6 s
WINDOW_CVARS=(+set com_maxfps 60 +set in_mouse 0 +set r_fullscreen 0 +set r_mode -1 +set r_customwidth 1280 +set r_customheight 720 +set s_volume 0 +set s_musicvolume 0)
NET_CVARS=(+set sv_master1 "" +set sv_master2 "" +set sv_master3 "" +set sv_master4 "" +set sv_master5 "" +set net_enabled 1 +set sv_lanForceRate 1 +set dedicated_lan 1)

usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------- arguments
mode="${1:-}"
case "$mode" in sp|mp|ded) shift ;; -h|--help) usage; exit 0 ;; *) print_err "first argument: sp, mp or ded"; usage; exit 1 ;; esac
home="" cfg="" exec_cmds="" baseline="" mouse=0 game="" install=1 mods=1 clean=0 debug=0 timeout_s=$DEFAULT_TIMEOUT grep_re="$DEFAULT_GREP" case_sensitive=0
install_args=()
while [[ $# -gt 0 ]]; do
	case "$1" in
		--home)              home="$2"; shift 2 ;;
		--cfg)               cfg="$2"; shift 2 ;;
		--exec)              exec_cmds="$2"; shift 2 ;;
		-g|--game)           game="$2"; shift 2 ;;
		--only|--exclude)    install_args+=("$1" "$2"); shift 2 ;;
		--no-install)        install=0; shift ;;
		--no-mods)           mods=0; shift ;;
		--timeout)           timeout_s="$2"; shift 2 ;;
		--grep)              grep_re="$2"; shift 2 ;;
		--baseline)          baseline="$2"; shift 2 ;;
		-c|--case-sensitive) case_sensitive=1; shift ;;
		--clean)             clean=1; shift ;;
		--mouse)             mouse=1; shift ;;
		-d|--debug)          debug=1; shift ;;
		-h|--help)           usage; exit 0 ;;
		*)                   if [[ -z "$cfg" && -f "$1" ]]; then cfg="$1"; shift; else print_err "unknown argument: $1"; exit 1; fi ;;
	esac
done
if [[ -z "$game" ]]; then
	prefix="$(sed -n 's/^CMAKE_INSTALL_PREFIX:[A-Z]*=//p' "$BUILD_DIR/CMakeCache.txt" 2>/dev/null || true)"
	game="$prefix/$INSTALL_SUBDIR"
fi
[[ -f "$game/base/assets0.pk3" ]] || { print_err "no retail data in $game/base (--game <dir>)"; exit 1; }
[[ -n "$home" ]] || home="$(mktemp -d "${TMPDIR:-/tmp}/ojk_playermods.XXXXXX")"
[[ -n "$cfg" || -n "$exec_cmds" ]] || { print_err "give --cfg <file> or --exec \"cmd; cmd\""; exit 1; }

case "$mode" in
	sp)  exe="openjk_sp.$ARCH"; modules=("code/game/jagame${ARCH}.so"); renderers=("code/rd-vanilla/rdsp-vanilla_${ARCH}.so") ;;
	mp)  exe="openjk.$ARCH"; modules=("codemp/game/jampgame${ARCH}.so" "codemp/cgame/cgame${ARCH}.so" "codemp/ui/ui${ARCH}.so")
	     renderers=("codemp/rd-vanilla/rd-vanilla_${ARCH}.so" "codemp/rd-rend2/rd-rend2_${ARCH}.so") ;;
	ded) exe="openjkded.$ARCH"; modules=("codemp/game/jampgame${ARCH}.so"); renderers=() ;;
esac

run() { if [[ $debug -eq 1 ]]; then printf '%q ' "$@"; printf '\n'; else "$@"; fi; }

# ---------------------------------------------------------------- the home
print_header "player mods test: $mode"
print_key "home" "$home"
print_key "game data" "$game"
run mkdir -p "$home/base" "$home/bin" "$home/$TEST_GAME"
if [[ $mods -eq 1 && $install -eq 1 ]]; then
	if [[ $debug -eq 1 ]]; then
		printf '%q ' "$SCRIPT_DIR/install_player_mods.sh" --dest "$home/base" --game "$game" "${install_args[@]}"; printf '\n'
	else
		"$SCRIPT_DIR/install_player_mods.sh" --dest "$home/base" --game "$game" "${install_args[@]}" | tail -1
	fi
elif [[ $mods -eq 0 && -f "$home/base/player_mods_manifest.txt" ]]; then
	run "$SCRIPT_DIR/install_player_mods.sh" --dest "$home/base" --uninstall
fi
run cp -f "$BUILD_DIR/$exe" "$home/bin/"
for r in "${renderers[@]}"; do run cp -f "$BUILD_DIR/$r" "$home/bin/"; done
for m in "${modules[@]}"; do run cp -f "$BUILD_DIR/$m" "$home/$TEST_GAME/"; done

cfg_file="$home/$TEST_GAME/$CFG_NAME"
if [[ $debug -eq 1 ]]; then
	echo "# then $cfg_file gets the test commands, one per line"
elif [[ -n "$cfg" ]]; then
	cp -f "$cfg" "$cfg_file"
else
	tr ';' '\n' <<< "$exec_cmds" | sed 's/^ *//; s/ *$//' | grep -v '^$' > "$cfg_file"
fi
log="$home/$TEST_GAME/$LOG_NAME"
[[ $debug -eq 1 ]] || rm -f "$log"

# ---------------------------------------------------------------- run
args=(+set fs_homepath "$home" +set fs_basepath "$game" +set fs_cdpath "" +set fs_game "$TEST_GAME"
	+set developer 1 +set logfile 2 +set com_hunkmegs 512 +set bot_enable 1 "${NET_CVARS[@]}")
case "$mode" in
	ded) args+=(+set dedicated 1) ;;
	*)   args+=("${WINDOW_CVARS[@]}")
	     # --mouse: menu input from a driver (sp_menu_check.sh) - the mouse is read but never grabbed
	     [[ $mouse -eq 1 ]] && args+=(+set in_mouse 1 +set in_nograb 1) ;;
esac
args+=(+exec "$CFG_NAME")
print_key "run" "$exe (timeout ${timeout_s}s)"
status=0
if [[ $debug -eq 1 ]]; then
	printf '(cd %q && timeout %q ./%q' "$home/bin" "$timeout_s" "$exe"; printf ' %q' "${args[@]}"; printf ')\n'
else
	rm -f "$home"/ld.*
	# LD_DEBUG=files records every library the run loads: the proof of which modules were used
	(cd "$home/bin" && LD_DEBUG=files LD_DEBUG_OUTPUT="$home/ld" timeout "$timeout_s" "./$exe" "${args[@]}" < /dev/null > "$home/stdout.log" 2>&1) || status=$?
fi

# ---------------------------------------------------------------- scan
grep_flags=(-n -E); [[ $case_sensitive -eq 1 ]] || grep_flags+=(-i)
if [[ $debug -eq 1 ]]; then
	printf 'grep %s %q %q\n' "${grep_flags[*]}" "$grep_re" "$log"
	exit 0
fi
[[ -f "$log" ]] || log="$home/stdout.log"
case $status in
	0)   print_ok "exited cleanly" ;;
	124) print_warn "timed out after ${timeout_s}s (killed)" ;;
	*)   print_err "exit status $status" ;;
esac
for m in "${modules[@]}" "${renderers[@]}"; do
	so="$(basename "$m")"
	used="$(cat "$home"/ld.* 2>/dev/null | sed -n "s/.*file=\([^ ]*${so}\) .*/\1/p" | sort -u | head -1)"
	# the engine runs in $home/bin, so a renderer loaded from there shows up as ./<so>
	if [[ "$used" == "$home/$TEST_GAME/$so" || "$used" == "$home/bin/$so" || "$used" == "./$so" ]]; then
		print_ok "loaded the fork's $so ($used)"
	elif [[ -n "$used" ]]; then
		print_err "loaded $so from $used, not the fork's build"
	elif [[ "$so" != rd-rend2* ]]; then
		print_warn "$so was not loaded"
	fi
done
strip_time() { sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8} )+//'; }  # some lines carry it twice
hits="$(strip_time < "$log" | grep -v -E -- "$PROBE_RE" | grep "${grep_flags[@]}" -- "$grep_re" || true)"
if [[ -n "$baseline" && -f "$baseline" && -n "$hits" ]]; then
	hits="$(grep -vxF -f <(strip_time < "$baseline") <<< "$(sed -E 's/^[0-9]+://' <<< "$hits")" || true)"
fi
if [[ -n "$hits" ]]; then
	print_header "log lines matching the error filter ($(wc -l <<< "$hits")):"
	printf '%s\n' "$hits"
else
	print_ok "no log lines match the error filter"
fi
shots="$home/$TEST_GAME/screenshots"
[[ -d "$shots" ]] && print_key "screenshots" "$shots ($(ls "$shots" | wc -l))"
print_key "log" "$log"
if [[ $clean -eq 1 ]]; then rm -rf -- "$home"; print_key "removed" "$home"; fi
exit $status
