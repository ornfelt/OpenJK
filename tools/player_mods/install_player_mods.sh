#!/usr/bin/env bash
# Installs the Jedi Academy player model mods into an OpenJK base/ dir.
#
# Copies every mod's pk3(s) from the players dir (one dir per mod) into base/, minus the
# alternative variants player_mods.conf skips, plus the loose files it lists as `extra` and the
# fork's own files in tools/player_mods/base/ (the default modelscale.cfg ...). It writes a
# manifest (player_mods_manifest.txt in base/) so --uninstall removes exactly what it installed,
# never overwrites a file it did not install, and lists the pk3s that replace stock files.
# The mods themselves are never changed; pk3s are only copied (and listed as zips).
#
# Usage examples:
#   install everything into the OpenJK homepath's base/:
#     ./install_player_mods.sh
#   players dir given positionally / by name:
#     ./install_player_mods.sh ~/Downloads/star_wars_ja_mods/players
#     ./install_player_mods.sh --players ~/Downloads/star_wars_ja_mods/players
#   a throwaway base/ for tests:
#     ./install_player_mods.sh --dest /tmp/ojk_test/base
#   leave mods (or single pk3s) out / add only some (comma separated or repeated, case-insensitive):
#     ./install_player_mods.sh --exclude BabyYoda,hs_anakin/HS-anakin_saber-SP.pk3
#     ./install_player_mods.sh --only T_Yoda --only grievousvm
#   case-sensitive matching of --only / --exclude:
#     ./install_player_mods.sh --only T_Yoda -c
#   remove what was installed (all, or only some mods):
#     ./install_player_mods.sh --uninstall
#     ./install_player_mods.sh --uninstall --only BabyYoda
#   print the equivalent shell commands instead of running them:
#     ./install_player_mods.sh --debug --dest /tmp/ojk_test/base

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
CONF_FILE="$SCRIPT_DIR/player_mods.conf"
FORK_BASE_DIR="$SCRIPT_DIR/base"
MANIFEST_NAME="player_mods_manifest.txt"
FORK_SOURCE="fork"                       # manifest source tag of the fork's own files
DEFAULT_PLAYERS="$HOME/Downloads/star_wars_ja_mods/players"
INSTALL_SUBDIR="JediAcademy"             # OpenJK's JKAInstallDir under CMAKE_INSTALL_PREFIX
case "$(uname -s)" in
	Darwin) DEFAULT_HOMEPATH="$HOME/Library/Application Support/OpenJK" ;;
	*)      DEFAULT_HOMEPATH="${XDG_DATA_HOME:-$HOME/.local/share}/openjk" ;;
esac

usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------- arguments
players="" dest="" game="" uninstall=0 debug=0 case_sensitive=0
only=() exclude=()
split_list() { local IFS=','; read -r -a _items <<< "$1"; }
while [[ $# -gt 0 ]]; do
	case "$1" in
		-p|--players)        players="$2"; shift 2 ;;
		--dest)              dest="$2"; shift 2 ;;
		-g|--game)           game="$2"; shift 2 ;;
		--only)              split_list "$2"; only+=("${_items[@]}"); shift 2 ;;
		--exclude)           split_list "$2"; exclude+=("${_items[@]}"); shift 2 ;;
		-c|--case-sensitive) case_sensitive=1; shift ;;
		-u|--uninstall)      uninstall=1; shift ;;
		-d|--debug)          debug=1; shift ;;
		-h|--help)           usage; exit 0 ;;
		-*)                  print_err "unknown option: $1"; usage; exit 1 ;;
		*)                   if [[ -z "$players" ]]; then players="$1"; shift; else print_err "unexpected argument: $1"; exit 1; fi ;;
	esac
done
players="${players:-$DEFAULT_PLAYERS}"
dest="${dest:-$DEFAULT_HOMEPATH/base}"
if [[ -z "$game" ]]; then
	prefix="$(sed -n 's/^CMAKE_INSTALL_PREFIX:[A-Z]*=//p' "$REPO_DIR/build/CMakeCache.txt" 2>/dev/null || true)"
	game="${prefix:+$prefix/$INSTALL_SUBDIR}"
	[[ -d "$game/base" ]] || game="$DEFAULT_HOMEPATH/$INSTALL_SUBDIR"
fi
manifest="$dest/$MANIFEST_NAME"

# ---------------------------------------------------------------- helpers
lower() { if [[ $case_sensitive -eq 1 ]]; then printf '%s' "$1"; else printf '%s' "${1,,}"; fi; }

# matches(mod, rel, list...): the mod dir, "mod/rel" or the file name is in the list
matches() {
	local mod rel item
	mod="$(lower "$1")"; rel="$(lower "$2")"; shift 2
	for item in "$@"; do
		item="$(lower "$item")"
		[[ "$item" == "$mod" || "$item" == "$mod/$rel" || "$item" == "${rel##*/}" ]] && return 0
	done
	return 1
}

selected() {  # selected(mod, rel): --only / --exclude
	if [[ ${#only[@]} -gt 0 ]] && ! matches "$1" "$2" "${only[@]}"; then return 1; fi
	if [[ ${#exclude[@]} -gt 0 ]] && matches "$1" "$2" "${exclude[@]}"; then return 1; fi
	return 0
}

conf_entries() {  # conf_entries(keyword): the "mod/path" values of that keyword
	[[ -f "$CONF_FILE" ]] || return 0
	local kw rest
	while read -r kw rest; do
		[[ -z "$kw" || "$kw" == \#* ]] && continue
		[[ "${kw,,}" == "$1" ]] && printf '%s\n' "$rest"
	done < "$CONF_FILE"
}

declare -A skip_set=()
while IFS= read -r e; do skip_set["${e,,}"]=1; done < <(conf_entries skip)

sha_of() { sha256sum -- "$1" | cut -d' ' -f1; }

declare -A man_sha=() man_src=()
if [[ -f "$manifest" ]]; then
	while IFS=$'\t' read -r sha name src; do
		[[ -z "$sha" || "$sha" == \#* ]] && continue
		man_sha["$name"]="$sha"; man_src["$name"]="$src"
	done < "$manifest"
fi

run() {  # run a command, or print it in --debug
	if [[ $debug -eq 1 ]]; then printf '%q ' "$@"; printf '\n'; else "$@"; fi
}

write_manifest() {
	local name
	if [[ $debug -eq 1 ]]; then
		echo "# then $manifest is rewritten: <sha256> TAB <file> TAB <source> per installed file"
		return
	fi
	{
		echo "# written by tools/player_mods/install_player_mods.sh - do not edit"
		while IFS= read -r name; do
			[[ -n "$name" ]] && printf '%s\t%s\t%s\n' "${man_sha[$name]}" "$name" "${man_src[$name]}"
		done < <(printf '%s\n' "${!man_sha[@]}" | sort -f)
	} > "$manifest"
	if [[ ${#man_sha[@]} -eq 0 ]]; then rm -f -- "$manifest"; fi
}

# ---------------------------------------------------------------- uninstall
if [[ $uninstall -eq 1 ]]; then
	print_header "uninstalling player mods from $dest"
	[[ ${#man_sha[@]} -gt 0 ]] || { print_warn "no $MANIFEST_NAME in $dest: nothing installed"; exit 0; }
	removed=0 kept=0
	while IFS= read -r name; do
		src="${man_src[$name]}"
		selected "${src%%/*}" "${src#*/}" || continue
		file="$dest/$name"
		if [[ ! -e "$file" ]]; then
			print_warn "  already gone: $name"
		elif [[ "$(sha_of "$file")" != "${man_sha[$name]}" ]]; then
			print_warn "  changed since it was installed, kept: $name"; kept=$((kept + 1)); continue
		else
			run rm -- "$file"; removed=$((removed + 1))
		fi
		unset 'man_sha[$name]' 'man_src[$name]'
	done < <(printf '%s\n' "${!man_sha[@]}" | sort -f)
	write_manifest
	print_ok "removed $removed file(s), kept $kept"
	exit 0
fi

# ---------------------------------------------------------------- install
[[ -d "$players" ]] || { print_err "players dir not found: $players"; exit 1; }
print_header "installing player mods"
print_key "from" "$players"
print_key "into" "$dest"
print_key "stock" "$game/base"

# what to copy: (source path, manifest source "mod/rel")
sources=() tags=()
for moddir in "$players"/*/; do
	mod="$(basename "$moddir")"
	while IFS= read -r -d '' pk3; do
		rel="${pk3#"$moddir"}"
		if [[ -n "${skip_set["${mod,,}/${rel,,}"]+x}" ]]; then continue; fi
		[[ "$rel" == */* && -n "$(conf_entries ignore | grep -Fix -- "$mod/${rel%%/*}" || true)" ]] && continue
		selected "$mod" "$rel" || continue
		sources+=("$pk3"); tags+=("$mod/$rel")
	done < <(find "$moddir" -type f -iname '*.pk3' -print0 | sort -zf)
done
while IFS= read -r e; do
	mod="${e%%/*}" rel="${e#*/}"
	[[ -f "$players/$e" ]] || { print_warn "extra file not found: $e"; continue; }
	selected "$mod" "$rel" || continue
	sources+=("$players/$e"); tags+=("$e")
done < <(conf_entries extra)
if [[ -d "$FORK_BASE_DIR" && ${#only[@]} -eq 0 ]]; then
	while IFS= read -r -d '' f; do
		sources+=("$f"); tags+=("$FORK_SOURCE/${f#"$FORK_BASE_DIR"/}")
	done < <(find "$FORK_BASE_DIR" -maxdepth 1 -type f -print0 | sort -zf)
fi
[[ ${#sources[@]} -gt 0 ]] || { print_warn "nothing selected"; exit 0; }

run mkdir -p -- "$dest"
declare -A taken=()
installed=0 updated=0 same=0 refused=0
for i in "${!sources[@]}"; do
	src="${sources[$i]}" tag="${tags[$i]}" name="$(basename "${sources[$i]}")"
	if [[ -n "${taken["${name,,}"]+x}" ]]; then
		print_err "  two sources for $name: ${taken["${name,,}"]} and $tag - skipped the second"; refused=$((refused + 1)); continue
	fi
	taken["${name,,}"]="$tag"
	target="$dest/$name"
	new_sha="$(sha_of "$src")"
	if [[ -e "$target" ]]; then
		if [[ -z "${man_sha[$name]+x}" ]]; then
			print_warn "  not installed by this script, left alone: $name"; refused=$((refused + 1)); continue
		fi
		cur_sha="$(sha_of "$target")"
		if [[ "$cur_sha" == "$new_sha" ]]; then
			same=$((same + 1)); man_src["$name"]="$tag"; continue
		fi
		if [[ "$cur_sha" != "${man_sha[$name]}" ]]; then
			print_warn "  changed since it was installed, left alone: $name"; refused=$((refused + 1)); continue
		fi
		updated=$((updated + 1))
	else
		installed=$((installed + 1))
	fi
	run cp -- "$src" "$target"
	man_sha["$name"]="$new_sha"; man_src["$name"]="$tag"
done
write_manifest

# ---------------------------------------------------------------- pk3s replacing stock files
if compgen -G "$game/base/assets*.pk3" > /dev/null; then
	print_header "pk3s that replace stock files (exclude with --exclude <mod>/<pk3>)"
	pk3s=()
	for i in "${!sources[@]}"; do [[ "${sources[$i],,}" == *.pk3 ]] && pk3s+=("${sources[$i]}"); done
	python3 -I - "$game/base" "${pk3s[@]}" <<'PY' || print_warn "could not list the stock overrides"
import glob, os, sys, zipfile
stock = set()
for p in sorted(glob.glob(os.path.join(sys.argv[1], "assets*.pk3"))):
	with zipfile.ZipFile(p) as z:
		stock.update(n.replace("\\", "/").lower() for n in z.namelist() if not n.endswith("/"))
for p in sys.argv[2:]:
	with zipfile.ZipFile(p) as z:
		hits = sorted({n.replace("\\", "/").lower() for n in z.namelist()} & stock)
	if hits:
		more = " ..." if len(hits) > 4 else ""
		print(f"  {os.path.basename(os.path.dirname(p))}/{os.path.basename(p)}: {len(hits)}: {', '.join(hits[:4])}{more}")
PY
else
	print_warn "no assets*.pk3 in $game/base: stock overrides not listed (--game <dir>)"
fi

print_ok "installed $installed, updated $updated, unchanged $same, left alone $refused - manifest $manifest"
