#!/usr/bin/env bash
# Checks that the fork and a stock OpenJK MP still play together with the player mods installed:
#
#   fork-server   the fork's dedicated server (run_test.sh ded, g_modelScale on) and a stock client
#                 (the install's openjk.x86_64 and base/ modules, i.e. the retail protocol) joining
#                 it: the client changes to a scaled model, uses /modelscale (handled by the fork
#                 server), moves, crouches, asks for `rcon modelscales` and picks t_yoda (the stock
#                 cgame draws Kyle for a custom skeleton).
#   stock-server  the other way round: the install's openjkded.x86_64 with its stock jampgame and a
#                 fork client (run_test.sh mp): no scaling (no g_modelScale serverinfo key), the
#                 server does not know /modelscale, t_yoda falls back to Kyle.
#
# Both sides get their own throwaway home with the mods installed; the stock side runs the install's
# binaries in place (read only) and its home holds only base/ (no fs_game modules), so the stock
# modules are loaded - proven by LD_DEBUG=files, as run_test.sh does for the fork side. No master
# servers, LAN only, a fixed port on 127.0.0.1. The client ends with `rcon quit`. Needs a display.
# Prints the client log's prediction misses and error lines and makes one contact sheet per
# direction (ImageMagick montage).
#
# Usage examples:
#   both directions in a new temp dir:
#     ./interop_check.sh
#   one direction, homes under a given dir (kept), another port:
#     ./interop_check.sh fork-server --home /tmp/ojk_interop --port 29180
#     ./interop_check.sh --direction stock-server --home /tmp/ojk_interop
#   the stock build from another install dir:
#     ./interop_check.sh --game ~/games/JediAcademy
#   remove the homes afterwards:
#     ./interop_check.sh --clean
#   print the equivalent shell commands instead of running them:
#     ./interop_check.sh --debug

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
INSTALL_SUBDIR="JediAcademy"
ARCH="x86_64"
TEST_GAME="playermods_test"			# run_test.sh's mod dir; the stock server uses the same name
CFG_NAME="interop.cfg"
LOG_NAME="qconsole.log"
DEFAULT_PORT=29170
RCON_PASSWORD="playermods_interop"
SERVER_TIMEOUT=360					# seconds; the client's `rcon quit` normally ends the server first
CLIENT_TIMEOUT=300
SERVER_START_WAIT=60				# seconds to wait for the server's map to be up
SERVER_READY_RE="Hitch warning|------- Game Initialization -------|InitGame"
SERVER_HOLD_WAIT=12000				# server frames the server cfg waits before quitting on its own
MODEL_WAIT=330						# client frames per model change (the 3-userinfo-per-6-s limit)
SCALED_MODEL="grievous"				# 1.23 in the default modelscale.cfg
CMD_SCALE=50						# what the client asks /modelscale for
SKELETON_MODEL="t_yoda"				# on _humanoid_yoda.gla (g_customSkeletons)
BOT_NAME="Darth Malgus"				# a mod bot on a scaled model (psdarthmalgus 1.17)
WINDOW_CVARS=(+set com_maxfps 60 +set in_mouse 0 +set r_fullscreen 0 +set r_mode -1 +set r_customwidth 1280 +set r_customheight 720 +set s_volume 0 +set s_musicvolume 0)
NET_CVARS=(+set sv_master1 "" +set sv_master2 "" +set sv_master3 "" +set sv_master4 "" +set sv_master5 "" +set net_enabled 1 +set sv_lanForceRate 1 +set dedicated_lan 1)
ERROR_RE="couldn't|can't|cannot|warning|error|failed|not found|g2|ghoul|missing|default model|bad |exceeded|overflow"
PROBE_RE="^Can't find (.*\\.(wav|jpg|png|tga|surf|ste)|models/players/[^/]*/(sounds_[^/]*\\.cfg|PlayerChoice\\.txt))$"
MISS_RE="prediction (miss|error)"

usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------- arguments
direction="both" home="" game="" port=$DEFAULT_PORT clean=0 debug=0
while [[ $# -gt 0 ]]; do
	case "${1,,}" in
		fork-server|stock-server|both) direction="${1,,}"; shift ;;
		--direction)  direction="${2,,}"; shift 2 ;;
		--home)       home="$2"; shift 2 ;;
		-g|--game)    game="$2"; shift 2 ;;
		--port)       port="$2"; shift 2 ;;
		--clean)      clean=1; shift ;;
		-d|--debug)   debug=1; shift ;;
		-h|--help)    usage; exit 0 ;;
		*)            print_err "unknown argument: $1"; usage; exit 1 ;;
	esac
done
case "$direction" in fork-server|stock-server|both) ;; *) print_err "direction: fork-server, stock-server or both"; exit 1 ;; esac
if [[ -z "$game" ]]; then
	prefix="$(sed -n 's/^CMAKE_INSTALL_PREFIX:[A-Z]*=//p' "$BUILD_DIR/CMakeCache.txt" 2>/dev/null || true)"
	game="$prefix/$INSTALL_SUBDIR"
fi
for f in "openjk.$ARCH" "openjkded.$ARCH" "base/cgame$ARCH.so" "base/jampgame$ARCH.so" "base/assets0.pk3"; do
	[[ -f "$game/$f" ]] || { print_err "no $f in $game (--game <install dir>)"; exit 1; }
done
[[ -n "$home" ]] || home="$(mktemp -d "${TMPDIR:-/tmp}/ojk_interop.XXXXXX")"

run() { if [[ $debug -eq 1 ]]; then printf '%q ' "$@"; printf '\n'; else "$@"; fi; }

# ---------------------------------------------------------------- cfgs
server_cfg() {
	cat <<-EOF
	map mp/ffa1
	wait 200
	addbot "$BOT_NAME" 1
	wait $SERVER_HOLD_WAIT
	quit
	EOF
}

# $1: the screenshot prefix
client_cfg() {
	local p="$1"
	cat <<-EOF
	set cg_thirdPerson 1
	set cg_thirdPersonAngle 180
	set cg_thirdPersonRange 110
	set con_notifytime 0
	set cg_showmiss 1
	connect 127.0.0.1:$port
	wait 1200
	team free
	wait 120
	togglemenu
	wait 300
	echo @@ interop: stock model
	screenshot ${p}_0_kyle
	wait 20
	echo @@ interop: model $SCALED_MODEL
	model $SCALED_MODEL
	wait $MODEL_WAIT
	screenshot ${p}_1_$SCALED_MODEL
	wait 20
	echo @@ interop: move, jump, crouch
	+forward
	wait 90
	-forward
	+moveup
	wait 30
	-moveup
	wait 60
	+movedown
	wait 90
	screenshot ${p}_2_crouch
	-movedown
	wait 60
	echo @@ interop: modelscale $CMD_SCALE
	modelscale $CMD_SCALE
	wait 120
	screenshot ${p}_3_modelscale$CMD_SCALE
	wait 20
	+back
	wait 60
	-back
	wait 30
	echo @@ interop: rcon modelscales
	rconpassword $RCON_PASSWORD
	rcon modelscales
	wait 120
	echo @@ interop: model $SKELETON_MODEL
	modelscale default
	model $SKELETON_MODEL
	wait $MODEL_WAIT
	screenshot ${p}_4_$SKELETON_MODEL
	wait 20
	echo @@ interop: done
	rcon quit
	wait 120
	quit
	EOF
}

# $1: home, $2: the .so name -> the path it was loaded from (LD_DEBUG=files output; only a library
# that was really loaded gets "calling init", the failed search probes only "file=")
loaded_from() { cat "$1"/ld.* 2>/dev/null | sed -n "s/.*calling init: \([^ ]*$2\)$/\1/p" | sort -u | head -1; }

# $1: home, $2: so, $3: expected path ("" = any path outside the home)
check_loaded() {
	local used; used="$(loaded_from "$1" "$2")"
	if [[ -z "$used" ]]; then
		print_err "$2 was not loaded"; return 1
	elif [[ "$used" == "$3" ]]; then
		print_ok "loaded $2 from $used"
	else
		print_err "loaded $2 from $used, expected $3"; return 1
	fi
}

wait_for_server() {
	local log="$1" waited=0
	while (( waited < SERVER_START_WAIT )); do
		[[ -f "$log" ]] && grep -q -E "$SERVER_READY_RE" "$log" && { sleep 3; return 0; }
		sleep 1; waited=$((waited + 1))
	done
	return 1
}

# $1: client log, $2: screenshot dir, $3: sheet path
report_client() {
	local log="$1" shots="$2" sheet="$3" misses hits
	strip_time() { sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8} )+//'; }
	[[ -f "$log" ]] || { print_err "no client log $log"; return; }
	misses="$(strip_time < "$log" | grep -c -i -E "$MISS_RE" || true)"
	print_key "prediction misses" "$misses"
	strip_time < "$log" | grep -i -E "$MISS_RE" | sort | uniq -c | sort -rn | head -5 || true
	print_header "client log, per check (@@) error lines and server replies:"
	strip_time < "$log" | grep -v -E -- "$PROBE_RE" | grep -i -E -- "^@@|$ERROR_RE|modelscale|unknown|scale|skeleton" | grep -v -i -E "$MISS_RE|^GL_" || true
	if [[ -d "$shots" ]] && command -v montage > /dev/null; then
		montage "$shots"/*.jpg -tile 5x1 -geometry 512x288+4+4 -label '%t' "$sheet" 2>/dev/null && print_key "contact sheet" "$sheet"
	fi
}

# ---------------------------------------------------------------- fork server, stock client
fork_server() {
	local sh="$home/fork_server" ch="$home/stock_client" spid status=0
	print_header "fork server, stock client (port $port)"
	run mkdir -p "$ch/base"
	if [[ $debug -eq 1 ]]; then
		printf '%q ' "$SCRIPT_DIR/run_test.sh" ded --home "$sh" --timeout "$SERVER_TIMEOUT" --set net_port "$port" --set rconpassword "$RCON_PASSWORD" --cfg "<server cfg>"; printf '&\n'
		printf '%q ' "$SCRIPT_DIR/install_player_mods.sh" --dest "$ch/base" --game "$game"; printf '\n'
		printf '(cd %q && LD_DEBUG=files LD_DEBUG_OUTPUT=%q timeout %q ./openjk.%s' "$game" "$ch/ld" "$CLIENT_TIMEOUT" "$ARCH"
		printf ' %q' +set fs_homepath "$ch" +set fs_basepath "$game" +set fs_cdpath "" +set developer 1 +set logfile 2 "${WINDOW_CVARS[@]}" "${NET_CVARS[@]}" +exec "$CFG_NAME"; printf ')\n'
		return
	fi
	server_cfg > "$home/fork_server.cfg"
	"$SCRIPT_DIR/run_test.sh" ded --home "$sh" --timeout "$SERVER_TIMEOUT" --set net_port "$port" \
		--set rconpassword "$RCON_PASSWORD" --cfg "$home/fork_server.cfg" > "$home/fork_server.out" 2>&1 &
	spid=$!
	"$SCRIPT_DIR/install_player_mods.sh" --dest "$ch/base" --game "$game" | tail -1
	wait_for_server "$sh/$TEST_GAME/$LOG_NAME" || { print_err "the fork server did not come up (see $home/fork_server.out)"; kill $spid 2> /dev/null || true; return 1; }
	client_cfg fork_server > "$ch/base/$CFG_NAME"
	rm -f "$ch"/ld.*
	(cd "$game" && LD_DEBUG=files LD_DEBUG_OUTPUT="$ch/ld" timeout "$CLIENT_TIMEOUT" "./openjk.$ARCH" +set fs_homepath "$ch" \
		+set fs_basepath "$game" +set fs_cdpath "" +set developer 1 +set logfile 2 "${WINDOW_CVARS[@]}" "${NET_CVARS[@]}" \
		+exec "$CFG_NAME" < /dev/null > "$ch/stdout.log" 2>&1) || status=$?
	[[ $status -eq 0 ]] && print_ok "stock client exited cleanly" || print_err "stock client exit status $status"
	wait $spid || true
	print_header "fork server (run_test.sh):"
	sed -n '/exited\|timed out\|exit status\|loaded\|matching/,$p' "$home/fork_server.out"
	check_loaded "$ch" "cgame$ARCH.so" "$game/base/cgame$ARCH.so" || true
	check_loaded "$ch" "ui$ARCH.so" "$game/base/ui$ARCH.so" || true
	report_client "$(find "$ch" -name "$LOG_NAME" | head -1)" "$(find "$ch" -type d -name screenshots | head -1)" "$home/fork_server_sheet.jpg"
}

# ---------------------------------------------------------------- stock server, fork client
stock_server() {
	local sh="$home/stock_server" ch="$home/fork_client" spid status=0
	print_header "stock server, fork client (port $port)"
	run mkdir -p "$sh/base" "$sh/$TEST_GAME"
	if [[ $debug -eq 1 ]]; then
		printf '%q ' "$SCRIPT_DIR/install_player_mods.sh" --dest "$sh/base" --game "$game"; printf '\n'
		printf '(cd %q && LD_DEBUG=files LD_DEBUG_OUTPUT=%q timeout %q ./openjkded.%s' "$game" "$sh/ld" "$SERVER_TIMEOUT" "$ARCH"
		printf ' %q' +set fs_homepath "$sh" +set fs_basepath "$game" +set fs_cdpath "" +set fs_game "$TEST_GAME" +set dedicated 1 \
			+set net_port "$port" +set rconpassword "$RCON_PASSWORD" +set developer 1 +set logfile 2 +set bot_enable 1 "${NET_CVARS[@]}" +exec "$CFG_NAME"; printf ') &\n'
		printf '%q ' "$SCRIPT_DIR/run_test.sh" mp --home "$ch" --timeout "$CLIENT_TIMEOUT" --cfg "<client cfg>"; printf '\n'
		return
	fi
	"$SCRIPT_DIR/install_player_mods.sh" --dest "$sh/base" --game "$game" | tail -1
	server_cfg > "$sh/$TEST_GAME/$CFG_NAME"
	rm -f "$sh"/ld.* "$sh/$TEST_GAME/$LOG_NAME"
	(cd "$game" && LD_DEBUG=files LD_DEBUG_OUTPUT="$sh/ld" timeout "$SERVER_TIMEOUT" "./openjkded.$ARCH" +set fs_homepath "$sh" \
		+set fs_basepath "$game" +set fs_cdpath "" +set fs_game "$TEST_GAME" +set dedicated 1 +set net_port "$port" \
		+set rconpassword "$RCON_PASSWORD" +set developer 1 +set logfile 2 +set bot_enable 1 "${NET_CVARS[@]}" \
		+exec "$CFG_NAME" < /dev/null > "$sh/stdout.log" 2>&1) &
	spid=$!
	wait_for_server "$sh/$TEST_GAME/$LOG_NAME" || { print_err "the stock server did not come up (see $sh/stdout.log)"; kill $spid 2> /dev/null || true; return 1; }
	client_cfg stock_server > "$home/fork_client.cfg"
	"$SCRIPT_DIR/run_test.sh" mp --home "$ch" --timeout "$CLIENT_TIMEOUT" --cfg "$home/fork_client.cfg" || status=$?
	wait $spid || true
	check_loaded "$sh" "jampgame$ARCH.so" "$game/base/jampgame$ARCH.so" || true
	report_client "$ch/$TEST_GAME/$LOG_NAME" "$ch/$TEST_GAME/screenshots" "$home/stock_server_sheet.jpg"
	print_header "stock server log, modelscale lines:"
	grep -i -E "modelscale|unknown" "$sh/$TEST_GAME/$LOG_NAME" | head -10 || true
}

print_header "player mods interop check: $direction"
print_key "homes" "$home"
print_key "stock build" "$game"
case "$direction" in
	fork-server)  fork_server ;;
	stock-server) stock_server ;;
	both)         fork_server; stock_server ;;
esac
if [[ $clean -eq 1 && $debug -eq 0 ]]; then rm -rf -- "$home"; print_key "removed" "$home"; fi
