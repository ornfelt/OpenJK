#!/usr/bin/env bash
# Shows every player mod model at scale 100 and at its size next to a Kyle npc, on one contact
# sheet, so the sizes of modelscale.cfg (step 8 of PLAYER_MODS_STATUS.md) can be judged by eye.
#
# The sizes come from measure_heights.py --target heights.txt (the proposal) or, with --cfg, from a
# modelscale.cfg. It runs run_test.sh mp in a throwaway home: devmap mp/duel1, a Kyle npc in front
# of the player, the camera from the side at a fixed distance (cg_thirdPersonModelScale 0), then
# per model: model <m>; /modelscale 100; screenshot; /modelscale <size>; screenshot. No GUI input.
#
# Usage examples:
#   all mods installed into a fresh throwaway home, the sizes heights.txt proposes:
#     ./size_check.sh
#   in a given home, the mods already there:
#     ./size_check.sh --home /tmp/ojk_size --no-install
#   only some models (substrings of the model dir, case-insensitive), home positional:
#     ./size_check.sh /tmp/ojk_size --no-install --model yoda,grievous
#   the sizes of a modelscale.cfg instead of the proposal:
#     ./size_check.sh --home /tmp/ojk_size --no-install --cfg base/modelscale.cfg
#   the contact sheet somewhere else:
#     ./size_check.sh --sheet /tmp/sizes.jpg
#   print the commands instead of running them:
#     ./size_check.sh --debug

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
TEST_GAME="playermods_test"
TARGETS="$SCRIPT_DIR/heights.txt"
# meshes another listed model already shows, and the SP-only custom character dirs (jedi_*: no
# model_default.skin, they are head / torso / legs parts)
SKIP_RE='^(jedi_[^ ]*|hs_anakin2|t_yoda_mp|yodaflee) '
MODEL_WAIT=330                          # frames: the server takes 3 userinfo changes per 6 s
SCALE_WAIT=60
SHOT_CROP="1280x600+0+60"               # the 1280x720 window without most of the HUD
SHOT_GEOMETRY="384x180+2+2"
CAMERA_RANGE=200                        # cg_thirdPersonRange: the tallest model at 100 % stays in frame
RANGE_ALL="10 250"                      # g_modelScaleRange for the test: every size the cfg allows

usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

home="" sheet="" cfg_file="" models="" debug=0 install_args=()
while [[ $# -gt 0 ]]; do
	case "$1" in
		--home)           home="$2"; shift 2 ;;
		--sheet)          sheet="$2"; shift 2 ;;
		--cfg)            cfg_file="$2"; shift 2 ;;
		-m|--model)       models="$2"; shift 2 ;;
		--no-install)     install_args+=(--no-install); shift ;;
		--only|--exclude) install_args+=("$1" "$2"); shift 2 ;;
		-d|--debug)       debug=1; shift ;;
		-h|--help)        usage; exit 0 ;;
		-*)               print_err "unknown argument: $1"; usage; exit 1 ;;
		*)                home="$1"; shift ;;
	esac
done
[[ -n "$home" ]] || home="$(mktemp -d "${TMPDIR:-/tmp}/ojk_size.XXXXXX")"
sheet="${sheet:-$home/sizes.jpg}"
cfg="$home/size_check.cfg"
shots="$home/$TEST_GAME/screenshots"

# "<model> <percent>" per model: the proposal of heights.txt, or the sizes of a modelscale.cfg
size_list() {
	python3 -I "$SCRIPT_DIR/measure_heights.py" --base "$home/base" --target "$TARGETS" --sizes \
		${cfg_file:+--cfg "$cfg_file"} ${models:+--model "$models"} | grep -Eiv "$SKIP_RE" || true
}

print_header "player model size check"
print_key "home" "$home"
print_key "sizes" "${cfg_file:-$TARGETS (proposal)}"
if [[ $debug -eq 1 ]]; then
	printf '%q ' "$SCRIPT_DIR/install_player_mods.sh" --dest "$home/base"; printf '\n'
	echo "python3 -I $(printf '%q' "$SCRIPT_DIR/measure_heights.py") --base $(printf '%q' "$home/base") --target $(printf '%q' "$TARGETS") --sizes${cfg_file:+ --cfg $(printf '%q' "$cfg_file")}  # <model> <percent>, minus $SKIP_RE"
	echo "# cfg $cfg: g_modelScaleRange \"$RANGE_ALL\", cg_thirdPersonModelScale 0, side camera, devmap mp/duel1, npc spawn kyle,"
	echo "#   per model: model <m>; wait $MODEL_WAIT; modelscale 100; wait $SCALE_WAIT; screenshot size_<n>_100; modelscale <p>; wait $SCALE_WAIT; screenshot size_<n>_<p>"
	printf '%q ' "$SCRIPT_DIR/run_test.sh" mp --home "$home" --no-install --cfg "$cfg" --timeout 900; printf '\n'
	echo "montage -crop $SHOT_CROP -label '%t' $(printf '%q' "$shots")/size_*.jpg -tile 4x -geometry $SHOT_GEOMETRY $(printf '%q' "$sheet")"
	exit 0
fi
command -v montage > /dev/null || { print_err "needs ImageMagick (montage)"; exit 1; }

mkdir -p "$home/base"
if [[ " ${install_args[*]:-} " != *" --no-install "* ]]; then
	"$SCRIPT_DIR/install_player_mods.sh" --dest "$home/base" "${install_args[@]}" | tail -1
fi
mapfile -t sizes < <(size_list)
[[ ${#sizes[@]} -gt 0 ]] || { print_err "no models to check"; exit 1; }
{
	echo "// generated by size_check.sh"
	echo "set g_modelScaleRange \"$RANGE_ALL\""
	echo "set cg_thirdPerson 1"
	echo "set cg_thirdPersonAngle 90"
	echo "set cg_thirdPersonRange $CAMERA_RANGE"
	echo "set cg_thirdPersonModelScale 0"
	echo "set con_notifytime 0"
	echo "devmap mp/duel1"
	echo "wait 600"
	echo "team free"
	echo "wait 120"
	echo "togglemenu"
	echo "wait 200"
	echo "npc spawn kyle"
	echo "wait 120"
	i=0
	for line in "${sizes[@]}"; do
		m="${line% *}" p="${line#* }" n="$(printf '%02d' $i)"
		echo "echo @@ size $m: $p"
		echo "model $m"
		echo "wait $MODEL_WAIT"
		echo "modelscale 100"
		echo "wait $SCALE_WAIT"
		echo "screenshot size_${n}_${m}_100"
		if [[ "$p" != 100 ]]; then
			echo "modelscale $p"
			echo "wait $SCALE_WAIT"
			echo "screenshot size_${n}_${m}_${p}"
		fi
		i=$((i + 1))
	done
	echo "echo @@ end"
	echo "quit"
} > "$cfg"
print_key "models" "${#sizes[@]}"

rm -rf "$shots"
"$SCRIPT_DIR/run_test.sh" mp --home "$home" --no-install --cfg "$cfg" --timeout 900 > "$home/run.txt" 2>&1 || true
grep -E "exited|status|timed|loaded" "$home/run.txt" || true
files=("$shots"/size_*.jpg)
[[ -e "${files[0]}" ]] || { print_warn "no screenshots"; exit 1; }
args=()
for f in "${files[@]}"; do
	b="$(basename "$f" .jpg)"; b="${b#size_[0-9][0-9]_}"
	args+=(-label "${b%_*} ${b##*_}%" "$f")
done
montage -crop "$SHOT_CROP" "${args[@]}" -tile 4x -geometry "$SHOT_GEOMETRY" -pointsize 12 "$sheet"
print_ok "${#files[@]} screenshot(s)"
print_key "sheet" "$sheet"
