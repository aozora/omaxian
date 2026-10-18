#!/bin/bash
# install-community-plugins.sh — copy selected community-plugins/ ports into
# ~/.config/omarchy/plugins/, optionally installing Debian apt deps declared in
# each port's omaxian.deps.json.
#
#   ./scripts/install-community-plugins.sh --list
#   ./scripts/install-community-plugins.sh <dir-or-id>…
#   ./scripts/install-community-plugins.sh --all
#   ./scripts/install-community-plugins.sh --skip-apt <dir-or-id>…
#
# Used by omaxian-install.sh (TUI). Not part of setup/install/deploy.
# Prefer ./omaxian-install.sh for first-time setup.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGINS_SRC="$REPO_DIR/community-plugins"
PLUGINS_DST="${HOME}/.config/omarchy/plugins"
OMARCHY_BIN="${HOME}/.local/share/omarchy/bin"

SKIP_APT=0
DO_LIST=0
DO_ALL=0
ARGS=()

usage() {
	sed -n '2,14p' "$0"
	exit 0
}

for arg in "$@"; do
	case "$arg" in
		--list)     DO_LIST=1 ;;
		--all)      DO_ALL=1 ;;
		--skip-apt) SKIP_APT=1 ;;
		-h|--help)  usage ;;
		*)          ARGS+=("$arg") ;;
	esac
done

if [ "$(id -u)" -eq 0 ]; then
	echo "!! refuse to install community plugins as root — run as your login user" >&2
	exit 1
fi

export PATH="$OMARCHY_BIN:$PATH"

# --- discovery ---------------------------------------------------------------
# Print: dir<TAB>id<TAB>name  (one per line)
list_plugins() {
	local dir manifest id name
	[ -d "$PLUGINS_SRC" ] || return 0
	for dir in "$PLUGINS_SRC"/*/; do
		[ -d "$dir" ] || continue
		manifest="${dir}manifest.json"
		[ -f "$manifest" ] || continue
		id=$(jq -r '.id // empty' "$manifest" 2>/dev/null) || continue
		[ -n "$id" ] || continue
		name=$(jq -r '.name // .id' "$manifest" 2>/dev/null)
		printf '%s\t%s\t%s\n' "$(basename "$dir")" "$id" "$name"
	done | sort -t$'\t' -k3,3
}

if (( DO_LIST )); then
	list_plugins
	exit 0
fi

# Resolve a user arg (directory name or plugin id) to an absolute plugin dir.
resolve_plugin_dir() {
	local arg="$1" line dir id
	if [ -d "$PLUGINS_SRC/$arg" ] && [ -f "$PLUGINS_SRC/$arg/manifest.json" ]; then
		printf '%s\n' "$PLUGINS_SRC/$arg"
		return 0
	fi
	while IFS=$'\t' read -r dir id _; do
		if [[ $arg == "$dir" || $arg == "$id" ]]; then
			printf '%s\n' "$PLUGINS_SRC/$dir"
			return 0
		fi
	done < <(list_plugins)
	return 1
}

SELECTED_DIRS=()
if (( DO_ALL )); then
	while IFS=$'\t' read -r dir _ _; do
		SELECTED_DIRS+=("$PLUGINS_SRC/$dir")
	done < <(list_plugins)
else
	if (( ${#ARGS[@]} == 0 )); then
		echo "usage: $0 [--skip-apt] <dir-or-id>… | --all | --list" >&2
		exit 2
	fi
	for arg in "${ARGS[@]}"; do
		if ! resolved=$(resolve_plugin_dir "$arg"); then
			echo "!! unknown community plugin: $arg" >&2
			exit 1
		fi
		SELECTED_DIRS+=("$resolved")
	done
fi

if (( ${#SELECTED_DIRS[@]} == 0 )); then
	echo ":: no community plugins to install"
	exit 0
fi

# Mutual exclusivity for speaker calibrators (when both somehow selected).
has_pulse=0
has_pipewire=0
for dir in "${SELECTED_DIRS[@]}"; do
	base=$(basename "$dir")
	[[ $base == omaxian-speaker-pulseaudio-calibrator ]] && has_pulse=1
	[[ $base == omaxian-speaker-pipewire-calibrator ]] && has_pipewire=1
done
if (( has_pulse && has_pipewire )); then
	echo "!! both PulseAudio and PipeWire speaker calibrators selected — pick one" >&2
	exit 1
fi

# --- apt deps from omaxian.deps.json -----------------------------------------
APT_PKGS=()
MANUAL_NOTES=()

collect_deps() {
	local dir deps apt_line manual_line pkg note
	for dir in "${SELECTED_DIRS[@]}"; do
		deps="$dir/omaxian.deps.json"
		[ -f "$deps" ] || continue
		while IFS= read -r pkg; do
			[ -n "$pkg" ] || continue
			APT_PKGS+=("$pkg")
		done < <(jq -r '.apt // [] | .[]' "$deps" 2>/dev/null)
		while IFS= read -r note; do
			[ -n "$note" ] || continue
			MANUAL_NOTES+=("$note")
		done < <(jq -r '.manual // [] | .[]' "$deps" 2>/dev/null)
	done
}

pkg_installed() {
	dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

collect_deps

NEED_APT=()
if (( ! SKIP_APT )) && (( ${#APT_PKGS[@]} > 0 )); then
	# Deduplicate
	mapfile -t APT_PKGS < <(printf '%s\n' "${APT_PKGS[@]}" | sort -u)
	for pkg in "${APT_PKGS[@]}"; do
		if pkg_installed "$pkg"; then
			continue
		fi
		NEED_APT+=("$pkg")
	done
fi

if (( ${#NEED_APT[@]} > 0 )); then
	echo ":: installing ${#NEED_APT[@]} apt package(s) for selected community plugins:"
	printf '   %s\n' "${NEED_APT[@]}"
	sudo apt-get install -y -- "${NEED_APT[@]}"
fi

# --- copy + validate + enable ------------------------------------------------
mkdir -p "$PLUGINS_DST"
SHELL_UP=0
if command -v omarchy-shell >/dev/null 2>&1 \
	&& [[ $(omarchy-shell shell ping 2>/dev/null || true) == ok ]]; then
	SHELL_UP=1
fi

INSTALLED_IDS=()
for dir in "${SELECTED_DIRS[@]}"; do
	manifest="$dir/manifest.json"
	id=$(jq -r '.id' "$manifest")
	name=$(jq -r '.name // .id' "$manifest")
	echo
	echo ":: $name ($id)"

	if command -v omarchy-plugin-validate >/dev/null 2>&1; then
		if ! omarchy-plugin-validate "$dir"; then
			echo "!! validation failed for $id — skipping" >&2
			continue
		fi
	else
		echo "!! omarchy-plugin-validate not on PATH — run scripts/install.sh first" >&2
		exit 1
	fi

	if command -v omarchy-plugin-check >/dev/null 2>&1; then
		if ! omarchy-plugin-check "$dir"; then
			echo "!! omarchy-plugin-check reported issues for $id — installing anyway (validate passed)"
		fi
	fi

	dest="$PLUGINS_DST/$id"
	mkdir -p "$dest"
	rsync -a --delete --exclude '.git' --exclude '.update.tmp.*' -- "$dir/" "$dest/"
	echo "   copied → $dest"
	INSTALLED_IDS+=("$id")

	if (( SHELL_UP )); then
		omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
		if omarchy-plugin-enable "$id" >/dev/null 2>&1; then
			echo "   enabled"
		else
			echo "   installed; enable later via Settings → Plugins"
		fi
	else
		echo "   installed; enable after first login (Settings → Plugins)"
	fi
done

echo
echo "========================================================================"
echo "Community plugins: installed ${#INSTALLED_IDS[@]}"
if (( ${#INSTALLED_IDS[@]} > 0 )); then
	printf '  %s\n' "${INSTALLED_IDS[@]}"
fi
if (( ${#MANUAL_NOTES[@]} > 0 )); then
	echo
	echo "Manual follow-up (not installable via apt):"
	# Deduplicate notes
	mapfile -t MANUAL_NOTES < <(printf '%s\n' "${MANUAL_NOTES[@]}" | sort -u)
	printf '  - %s\n' "${MANUAL_NOTES[@]}"
fi
echo "========================================================================"
