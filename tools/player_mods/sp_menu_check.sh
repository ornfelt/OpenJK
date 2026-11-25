#!/usr/bin/env bash
# Shows every species of the SP character creation menu (models/players/*/PlayerChoice.txt in the
# stock assets and the installed mods) in the fork's SP build and screenshots its name, so the
# "SP menu" cells of PLAYER_MODS_STATUS.md can be read off one contact sheet.
#
# It runs run_test.sh sp in a throwaway home with a cfg that waits, then sets ui_char_model to each
# species (the menu's species item shows @MENUS_<SPECIES> for the cvar's value) and screenshots.
# Reaching the menu takes two clicks - "New" in the main menu, "Next" in the new game menu - sent
# with xdotool only to the game's own window: found by its title, verified by its process holding
# this home on its command line, activated and checked to be the active window before each click.
# The mouse is read but not grabbed (run_test.sh --mouse: in_nograb 1).
#
# Usage examples:
#   all mods installed into a fresh throwaway home:
#     ./sp_menu_check.sh
#   in a given home, the mods already there:
#     ./sp_menu_check.sh --home /tmp/ojk_menu --no-install
#   only some mods (passed to the install script):
#     ./sp_menu_check.sh --only ST_REY_V2.3,T_Anavader
#   the contact sheet somewhere else:
#     ./sp_menu_check.sh --sheet /tmp/species.jpg
#   print the commands instead of running them:
#     ./sp_menu_check.sh --debug

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
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WINDOW_TITLE='^OpenJK \(SP\)$'          # CLIENT_WINDOW_TITLE in code/qcommon/q_shared.h
WIN_W=1280 WIN_H=720                    # run_test.sh's window (r_customwidth / height)
MENU_W=640 MENU_H=480                   # the menus' virtual screen
NEW_BUTTON="101 224"                    # ui/main.menu newgamebutton, rect 36 212 130 24: its middle
NEXT_BUTTON="520 456"                   # ui/newgame_first.menu nextbutton, rect 455 444 130 24
CLICK_WAIT_FRAMES=2400                  # cfg wait (60 fps) covering the window, menus and clicks
SHOT_WAIT_FRAMES=60
SHOT_CROP="640x60+30+120"               # the species row (the preview does not follow the cvar)
TEST_GAME="playermods_test"

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
[[ -n "$home" ]] || home="$(mktemp -d "${TMPDIR:-/tmp}/ojk_spmenu.XXXXXX")"
sheet="${sheet:-$home/sp_species.jpg}"
prefix="$(sed -n 's/^CMAKE_INSTALL_PREFIX:[A-Z]*=//p' "$REPO_DIR/build/CMakeCache.txt" 2>/dev/null || true)"
game="$prefix/JediAcademy"
players="$HOME/Downloads/star_wars_ja_mods/players"

# species -> the pk3 that ships it (stock assets, then the mods the inventory installs)
species_list() {
	python3 -I - "$game/base" "$home/base" <<'PY'
import glob, os, sys, zipfile
seen = {}
for d in sys.argv[1:]:
	for p in sorted(glob.glob(os.path.join(d, "*.pk3"))):
		with zipfile.ZipFile(p) as z:
			for n in z.namelist():
				l = n.replace("\\", "/").lower()
				if l.startswith("models/players/") and l.endswith("/playerchoice.txt") and l.count("/") == 3:
					seen.setdefault(l.split("/")[2], os.path.basename(p))
for name, pk3 in sorted(seen.items()):
	print(name, pk3)
PY
}

# the window, verified to belong to this run
find_window() {
	local id pid
	for id in $(xdotool search --onlyvisible --name "$WINDOW_TITLE" 2>/dev/null); do
		pid="$(xdotool getwindowpid "$id" 2>/dev/null || true)"
		[[ -n "$pid" ]] && tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -qF -- "$home" && { echo "$id"; return 0; }
	done
	return 1
}

# click_menu <window> <x> <y>: x y in menu coordinates. The menu cursor moves by the mouse's
# relative motion and clamps at 0 0: sweep from the window's far corner to 0 0, then move by x y.
click_menu() {
	local w="$1" x="$2" y="$3"
	xdotool windowactivate --sync "$w" 2>/dev/null || true
	if [[ "$(xdotool getactivewindow 2>/dev/null)" != "$w" ]]; then
		print_err "the game window is not the active window: no input sent"; return 1
	fi
	xdotool mousemove --window "$w" $((WIN_W - 1)) $((WIN_H - 1)); sleep 0.2
	xdotool mousemove --window "$w" 0 0; sleep 0.2
	xdotool mousemove --window "$w" 1 1; sleep 0.1
	xdotool mousemove --window "$w" 0 0; sleep 0.2
	xdotool mousemove --window "$w" "$x" "$y"; sleep 0.3
	[[ "$(xdotool getactivewindow 2>/dev/null)" == "$w" ]] || { print_err "focus lost before the click: no click sent"; return 1; }
	xdotool click --window "$w" 1
}

print_header "SP character menu check"
print_key "home" "$home"
cfg="$home/sp_menu.cfg"
if [[ $debug -eq 1 ]]; then
	printf '%q ' "$SCRIPT_DIR/install_player_mods.sh" --dest "$home/base"; printf '\n'
	echo "# cfg $cfg: wait $CLICK_WAIT_FRAMES, then per species: set ui_char_model <species>; wait $SHOT_WAIT_FRAMES; screenshot spmenu_<n>; quit"
	printf '%q ' "$SCRIPT_DIR/run_test.sh" sp --home "$home" --no-install --mouse --cfg "$cfg" --timeout 600; printf '&\n'
	echo "# then, on the window titled 'OpenJK (SP)' whose process has $home on its command line, once it is active:"
	echo "xdotool mousemove --window \$w $((WIN_W - 1)) $((WIN_H - 1)); xdotool mousemove --window \$w 0 0; xdotool mousemove --window \$w ${NEW_BUTTON% *} ${NEW_BUTTON#* }; xdotool click --window \$w 1"
	echo "xdotool mousemove --window \$w $((WIN_W - 1)) $((WIN_H - 1)); xdotool mousemove --window \$w 0 0; xdotool mousemove --window \$w ${NEXT_BUTTON% *} ${NEXT_BUTTON#* }; xdotool click --window \$w 1"
	echo "montage -crop $SHOT_CROP -label '%t' $home/$TEST_GAME/screenshots/spmenu_*.jpg -tile 3x -geometry 420x40+2+2 $(printf '%q' "$sheet")"
	exit 0
fi
command -v xdotool > /dev/null || { print_err "needs xdotool and a display"; exit 1; }
[[ -n "${DISPLAY:-}" ]] || { print_err "no DISPLAY: not run - needs a display"; exit 1; }

mkdir -p "$home/base"
if [[ " ${install_args[*]:-} " != *" --no-install "* ]]; then
	"$SCRIPT_DIR/install_player_mods.sh" --dest "$home/base" "${install_args[@]}" | tail -1
fi
mapfile -t species < <(species_list)
{
	echo "// generated by sp_menu_check.sh"
	echo "wait $CLICK_WAIT_FRAMES"
	i=0
	for line in "${species[@]}"; do
		name="${line%% *}" pk3="${line#* }" shot="$(printf 'spmenu_%03d' $i)"
		echo "echo @@ spmenu $pk3: $name [$shot]"
		echo "set ui_char_model $name"
		echo "wait $SHOT_WAIT_FRAMES"
		echo "screenshot $shot"
		echo "wait 20"
		i=$((i + 1))
	done
	echo "echo @@ end"
	echo "quit"
} > "$cfg"
print_key "species" "${#species[@]}"

rm -rf "$home/$TEST_GAME/screenshots"
"$SCRIPT_DIR/run_test.sh" sp --home "$home" --no-install --mouse --cfg "$cfg" --timeout 600 > "$home/run.txt" 2>&1 &
runner=$!
w=""
for _ in $(seq 1 240); do w="$(find_window || true)"; [[ -n "$w" ]] && break; sleep 0.5; done
if [[ -z "$w" ]]; then
	print_err "no game window found: no input sent"; wait "$runner" || true; exit 1
fi
print_key "window" "$w (verified: its process runs with this home)"
sleep 6   # the main menu
click_menu "$w" ${NEW_BUTTON} || { wait "$runner" || true; exit 1; }
sleep 3
click_menu "$w" ${NEXT_BUTTON} || { wait "$runner" || true; exit 1; }
print_ok "clicked New and Next; waiting for the run"
wait "$runner" || true
grep -E "exited|status|timed|loaded" "$home/run.txt" || true

shots=("$home/$TEST_GAME/screenshots"/spmenu_*.jpg)
if [[ -e "${shots[0]}" ]]; then
	args=()
	log="$home/$TEST_GAME/qconsole.log"
	while read -r shot label; do
		[[ -f "$home/$TEST_GAME/screenshots/$shot.jpg" ]] && args+=(-label "$shot $label" "$home/$TEST_GAME/screenshots/$shot.jpg")
	done < <(sed -E 's/^([0-9-]+ [0-9:]+ )+//' "$log" | sed -n -E 's/^@@ spmenu ([^:]*): (.*) \[(spmenu_[0-9]+)\]$/\3 \2 (\1)/p')
	montage -crop "$SHOT_CROP" "${args[@]}" -tile 3x -geometry 420x40+2+2 -pointsize 12 "$sheet"
	print_key "sheet" "$sheet"
else
	print_warn "no screenshots"
fi
