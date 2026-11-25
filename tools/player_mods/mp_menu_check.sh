#!/usr/bin/env bash
# Pages through the MP player model menu (the model grid of ui/jamp/ingame_player.menu that opens
# when a client joins) in the fork's MP build and puts every page on one contact sheet, so the
# "MP menu" cells of PLAYER_MODS_STATUS.md can be read off it.
#
# It runs run_test.sh mp in a throwaway home (devmap mp/duel1; the join menu opens by itself),
# moves the menu cursor over the grid and scrolls it a page per mouse wheel notch until the grid
# stops changing, grabbing each page with ImageMagick's import. Input and grabs go only to the
# game's own window: found by its title, verified by its process holding this home on its command
# line, activated and checked to be the active window before each wheel notch. The mouse is read
# but not grabbed (run_test.sh --mouse).
#
# Usage examples:
#   all mods installed into a fresh throwaway home:
#     ./mp_menu_check.sh
#   in a given home, the mods already there:
#     ./mp_menu_check.sh --home /tmp/ojk_menu --no-install
#   only some mods (passed to the install script):
#     ./mp_menu_check.sh --only ST_REY_V2.3,T_Anavader
#   the contact sheet somewhere else:
#     ./mp_menu_check.sh --sheet /tmp/models.jpg
#   print the commands instead of running them:
#     ./mp_menu_check.sh --debug

set -euo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WINDOW_TITLE='^OpenJK \(MP\)$'          # CLIENT_WINDOW_TITLE in codemp/qcommon/q_shared.h
WIN_W=1280 WIN_H=720                    # run_test.sh's window (r_customwidth / height)
GRID_POINT="200 180"                    # inside headlist, rect 20 90 404 194 (menu coordinates)
GRID_CROP="808x291+40+135"              # the same rect in window pixels (x2, x1.5)
MENU_WAIT_S=16                          # the map load and the join menu
MAX_PAGES=40
RUN_WAIT_FRAMES=4800                    # cfg wait (60 fps) before quit: longer than the paging

usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

home="" sheet="" debug=0 install_args=()
while [[ $# -gt 0 ]]; do
	case "$1" in
		--home)           home="$2"; shift 2 ;;
		--sheet)          sheet="$2"; shift 2 ;;
		--no-install)     install_args+=(--no-install); shift ;;
		--only|--exclude) install_args+=("$1" "$2"); shift 2 ;;
		-d|--debug)       debug=1; shift ;;
		-h|--help)        usage; exit 0 ;;
		*)                print_err "unknown argument: $1"; usage; exit 1 ;;
	esac
done
[[ -n "$home" ]] || home="$(mktemp -d "${TMPDIR:-/tmp}/ojk_mpmenu.XXXXXX")"
sheet="${sheet:-$home/mp_models.jpg}"
pages="$home/menu_pages"
cfg_cmds="set con_notifytime 0; devmap mp/duel1; wait $RUN_WAIT_FRAMES; quit"

find_window() {
	local id pid
	for id in $(xdotool search --onlyvisible --name "$WINDOW_TITLE" 2>/dev/null); do
		pid="$(xdotool getwindowpid "$id" 2>/dev/null || true)"
		[[ -n "$pid" ]] && tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -qF -- "$home" && { echo "$id"; return 0; }
	done
	return 1
}

is_active() { [[ "$(xdotool getactivewindow 2>/dev/null)" == "$1" ]]; }

# the menu cursor moves by relative motion and clamps at 0 0: sweep to 0 0, then move by x y
point_menu() {
	local w="$1" x="$2" y="$3"
	xdotool windowactivate --sync "$w" 2>/dev/null || true
	is_active "$w" || { print_err "the game window is not the active window: no input sent"; return 1; }
	xdotool mousemove --window "$w" $((WIN_W - 1)) $((WIN_H - 1)); sleep 0.2
	xdotool mousemove --window "$w" 0 0; sleep 0.2
	xdotool mousemove --window "$w" 1 1; sleep 0.1
	xdotool mousemove --window "$w" 0 0; sleep 0.2
	xdotool mousemove --window "$w" "$x" "$y"; sleep 0.3
}

print_header "MP player model menu check"
print_key "home" "$home"
if [[ $debug -eq 1 ]]; then
	printf '%q ' "$SCRIPT_DIR/install_player_mods.sh" --dest "$home/base"; printf '\n'
	printf '%q ' "$SCRIPT_DIR/run_test.sh" mp --home "$home" --no-install --mouse --exec "$cfg_cmds" --timeout 300; printf '&\n'
	echo "# then, on the window titled 'OpenJK (MP)' whose process has $home on its command line, once it is active:"
	echo "xdotool mousemove --window \$w $((WIN_W - 1)) $((WIN_H - 1)); xdotool mousemove --window \$w 0 0; xdotool mousemove --window \$w ${GRID_POINT% *} ${GRID_POINT#* }"
	echo "for n in \$(seq -w 0 $MAX_PAGES); do import -window \$w $pages/page_\$n.png; xdotool click --window \$w 5; sleep 0.8; done  # until two pages match"
	echo "montage -crop $GRID_CROP $pages/page_*.png -tile 2x -geometry 404x146+2+2 $(printf '%q' "$sheet")"
	exit 0
fi
for tool in xdotool import montage; do command -v "$tool" > /dev/null || { print_err "needs $tool"; exit 1; }; done
[[ -n "${DISPLAY:-}" ]] || { print_err "no DISPLAY: not run - needs a display"; exit 1; }

mkdir -p "$home/base"
if [[ " ${install_args[*]:-} " != *" --no-install "* ]]; then
	"$SCRIPT_DIR/install_player_mods.sh" --dest "$home/base" "${install_args[@]}" | tail -1
fi
rm -rf "$pages"; mkdir -p "$pages"
"$SCRIPT_DIR/run_test.sh" mp --home "$home" --no-install --mouse --exec "$cfg_cmds" --timeout 300 > "$home/run.txt" 2>&1 &
runner=$!
w=""
for _ in $(seq 1 240); do w="$(find_window || true)"; [[ -n "$w" ]] && break; sleep 0.5; done
[[ -n "$w" ]] || { print_err "no game window found: no input sent"; wait "$runner" || true; exit 1; }
print_key "window" "$w (verified: its process runs with this home)"
sleep "$MENU_WAIT_S"
point_menu "$w" ${GRID_POINT} || { wait "$runner" || true; exit 1; }

prev="" n=0
while [[ $n -lt $MAX_PAGES ]]; do
	page="$(printf '%s/page_%02d.png' "$pages" $n)"
	find_window > /dev/null || { print_warn "the window is gone"; break; }
	import -window "$w" "$page"
	sum="$(convert "$page" -crop "$GRID_CROP" +repage -scale 25% rgb:- | md5sum | cut -d' ' -f1)"
	if [[ "$sum" == "$prev" ]]; then rm -f "$page"; break; fi
	prev="$sum"; n=$((n + 1))
	is_active "$w" || { print_err "focus lost: no more input sent"; break; }
	xdotool click --window "$w" 5
	sleep 0.8
done
print_ok "$n page(s)"
wait "$runner" || true
grep -E "exited|status|timed" "$home/run.txt" || true
montage -crop "$GRID_CROP" "$pages"/page_*.png -tile 2x -geometry 404x146+2+2 "$sheet"
print_key "sheet" "$sheet"
