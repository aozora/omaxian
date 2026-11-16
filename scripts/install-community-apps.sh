#!/bin/bash
# install-community-apps.sh — run selected community-apps/*/install.sh ports.
#
#   ./scripts/install-community-apps.sh --list
#   ./scripts/install-community-apps.sh <dir>…
#   ./scripts/install-community-apps.sh --all
#   ./scripts/install-community-apps.sh --skip-apt <dir>…
#   ./scripts/install-community-apps.sh --report FILE <dir>…
#
# --report FILE writes one "ok<TAB>dir" / "failed<TAB>dir" line per app.
#
# Used by omaxian-install.sh (TUI). Not part of setup/install/deploy.
# Prefer ./omaxian-install.sh for first-time setup.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APPS_SRC="$REPO_DIR/community-apps"

SKIP_APT=0
DO_LIST=0
DO_ALL=0
REPORT=""
ARGS=()

usage() {
	sed -n '2,13p' "$0"
	exit 0
}

while (( $# > 0 )); do
	case "$1" in
		--list)     DO_LIST=1 ;;
		--all)      DO_ALL=1 ;;
		--skip-apt) SKIP_APT=1 ;;
		--report)
			[[ -n ${2:-} ]] || { echo "--report needs a file" >&2; exit 2; }
			REPORT=$2
			shift
			;;
		-h|--help)  usage ;;
		*)          ARGS+=("$1") ;;
	esac
	shift
done

if [ "$(id -u)" -eq 0 ]; then
	echo "!! refuse to install community apps as root — run as your login user" >&2
	exit 1
fi

# Friendly display name for checklist / logs (dir → label).
app_display_name() {
	local dir="$1"
	case "$dir" in
		disktree)                  echo "disktree" ;;
		folio)                     echo "Folio" ;;
		monologue)                 echo "Monologue" ;;
		omacalc)                   echo "Omacalc" ;;
		omacut)                    echo "Omacut" ;;
		omarchy-meeting-recorder)  echo "Meeting Recorder" ;;
		omawrite)                  echo "Omawrite" ;;
		plain)                     echo "Plain" ;;
		signed)                    echo "Signed" ;;
		*)
			# First Markdown H1 of README.md, strip " (Omaxian port)".
			local heading
			heading=$(awk '/^# /{sub(/^# /,""); print; exit}' "$APPS_SRC/$dir/README.md" 2>/dev/null || true)
			heading=${heading%% (Omaxian port)*}
			if [ -n "$heading" ]; then
				printf '%s\n' "$heading"
			else
				printf '%s\n' "$dir"
			fi
			;;
	esac
}

# --- discovery ---------------------------------------------------------------
# Print: dir<TAB>name  (one per line). Requires install.sh.
list_apps() {
	local dir name
	[ -d "$APPS_SRC" ] || return 0
	for dir in "$APPS_SRC"/*/; do
		[ -d "$dir" ] || continue
		[ -x "${dir}install.sh" ] || continue
		name=$(app_display_name "$(basename "$dir")")
		printf '%s\t%s\n' "$(basename "$dir")" "$name"
	done | sort -t$'\t' -k2,2
}

if (( DO_LIST )); then
	list_apps
	exit 0
fi

resolve_app_dir() {
	local arg="$1" line dir
	if [ -d "$APPS_SRC/$arg" ] && [ -x "$APPS_SRC/$arg/install.sh" ]; then
		printf '%s\n' "$APPS_SRC/$arg"
		return 0
	fi
	while IFS=$'\t' read -r dir _; do
		if [[ $arg == "$dir" ]]; then
			printf '%s\n' "$APPS_SRC/$dir"
			return 0
		fi
	done < <(list_apps)
	return 1
}

SELECTED_DIRS=()
if (( DO_ALL )); then
	while IFS=$'\t' read -r dir _; do
		SELECTED_DIRS+=("$APPS_SRC/$dir")
	done < <(list_apps)
else
	if (( ${#ARGS[@]} == 0 )); then
		echo "usage: $0 [--skip-apt] <dir>… | --all | --list" >&2
		exit 2
	fi
	for arg in "${ARGS[@]}"; do
		if ! resolved=$(resolve_app_dir "$arg"); then
			echo "!! unknown community app: $arg" >&2
			exit 1
		fi
		SELECTED_DIRS+=("$resolved")
	done
fi

if (( ${#SELECTED_DIRS[@]} == 0 )); then
	echo ":: no community apps to install"
	exit 0
fi

# --- install each app via its own install.sh ---------------------------------
INSTALLED=()
FAILED=()
n_item=0
for dir in "${SELECTED_DIRS[@]}"; do
	base=$(basename "$dir")
	name=$(app_display_name "$base")
	n_item=$(( n_item + 1 ))
	echo
	# "-- i/N" is what omaxian-install.sh reads to move its progress bar.
	echo "-- $n_item/${#SELECTED_DIRS[@]}  $name ($base)"
	install_args=()
	if (( SKIP_APT )); then
		install_args+=(--skip-apt)
	fi
	if (cd "$dir" && ./install.sh "${install_args[@]+"${install_args[@]}"}"); then
		INSTALLED+=("$base")
		echo "   ok → $name"
		[[ -z $REPORT ]] || printf 'ok\t%s\n' "$base" >>"$REPORT"
	else
		ec=$?
		echo "!! $name install failed (exit $ec)" >&2
		FAILED+=("$base")
		[[ -z $REPORT ]] || printf 'failed\t%s\n' "$base" >>"$REPORT"
	fi
done

# Manual notes from omaxian.deps.json (informational).
MANUAL_NOTES=()
for dir in "${SELECTED_DIRS[@]}"; do
	deps="$dir/omaxian.deps.json"
	[ -f "$deps" ] || continue
	while IFS= read -r note; do
		[ -n "$note" ] || continue
		MANUAL_NOTES+=("$note")
	done < <(jq -r '.manual // [] | .[]' "$deps" 2>/dev/null)
done

echo
echo "========================================================================"
echo "Community apps: installed ${#INSTALLED[@]}"
if (( ${#INSTALLED[@]} > 0 )); then
	printf '  %s\n' "${INSTALLED[@]}"
fi
if (( ${#FAILED[@]} > 0 )); then
	echo
	echo "Failed (${#FAILED[@]}):"
	printf '  %s\n' "${FAILED[@]}"
fi
if (( ${#MANUAL_NOTES[@]} > 0 )); then
	echo
	echo "Manual follow-up (not installable via apt):"
	mapfile -t MANUAL_NOTES < <(printf '%s\n' "${MANUAL_NOTES[@]}" | sort -u)
	printf '  - %s\n' "${MANUAL_NOTES[@]}"
fi
echo "========================================================================"

# Soft-fail: leave exit 0 so the TUI can finish after a partial install.
# Total failure still errors so a lone broken app is obvious outside the TUI.
if (( ${#FAILED[@]} > 0 && ${#INSTALLED[@]} == 0 )); then
	exit 1
fi
