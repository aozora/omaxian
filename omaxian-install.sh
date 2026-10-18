#!/bin/bash
# omaxian-install.sh — one-shot TUI installer for Omaxian (Devuan/Debian + X11 + i3).
#
# Orchestrates scripts/setup.sh → install.sh → deploy.sh, then optionally
# community plugins (with apt deps from omaxian.deps.json).
#
#   ./omaxian-install.sh
#   ./omaxian-install.sh --yes          # noninteractive: recommended + deploy, no plugins
#   OMAXIAN_INSTALL_NONINTERACTIVE=1 ./omaxian-install.sh
#
# Remote first-time: curl -fsSL …/bootstrap.sh | bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$REPO_DIR/scripts"
SETUP="$SCRIPTS/setup.sh"
INSTALL="$SCRIPTS/install.sh"
DEPLOY="$SCRIPTS/deploy.sh"
PLUGIN_HELPER="$SCRIPTS/install-community-plugins.sh"

NONINTERACTIVE=0
for arg in "$@"; do
	case "$arg" in
		--yes|-y)  NONINTERACTIVE=1 ;;
		-h|--help)
			sed -n '2,16p' "$0"
			exit 0
			;;
		*)
			echo "unknown option: $arg" >&2
			exit 2
			;;
	esac
done
if [[ ${OMAXIAN_INSTALL_NONINTERACTIVE:-0} == 1 ]]; then
	NONINTERACTIVE=1
fi

# --- privilege: never seed /root --------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
	if [ -z "${SUDO_USER:-}" ] || [ "$SUDO_USER" = root ]; then
		echo "!! refuse to install as root — run:  ./omaxian-install.sh" >&2
		exit 1
	fi
	echo ":: re-exec as $SUDO_USER (was root via sudo)"
	exec sudo -u "$SUDO_USER" -H "$0" "$@"
fi

for f in "$SETUP" "$INSTALL" "$DEPLOY" "$PLUGIN_HELPER"; do
	if [ ! -x "$f" ]; then
		echo "!! missing $f — wrong checkout?" >&2
		exit 1
	fi
done

# --- whiptail ---------------------------------------------------------------
ensure_whiptail() {
	if command -v whiptail >/dev/null 2>&1; then
		return 0
	fi
	echo ":: whiptail not found — installing…"
	sudo apt-get install -y whiptail || {
		echo "!! could not install whiptail — install the 'whiptail' package and re-run" >&2
		exit 1
	}
}

wt() {
	# Neon / newt: backtitle + title helpers
	whiptail --backtitle "Omaxian installer" "$@"
}

phase_banner() {
	local title="$1"
	echo
	echo "========================================================================"
	echo "$title"
	echo "========================================================================"
}

# --- package mode -----------------------------------------------------------
# Sets SETUP_FLAGS array: empty | --minimal | --optional
SETUP_FLAGS=()
PKG_LABEL="Recommended (default)"

choose_package_set() {
	local choice
	choice=$(wt --title "Package set" --radiolist \
		"Which system packages should setup install?\n\nRecommended covers bar widgets most people use." \
		15 72 3 \
		recommended "Required + recommended" ON \
		minimal "Required only (--minimal)" OFF \
		optional "Recommended + optional extras (--optional)" OFF \
		3>&1 1>&2 2>&3) || return 1
	case "$choice" in
		minimal)
			SETUP_FLAGS=(--minimal)
			PKG_LABEL="Minimal (required only)"
			;;
		optional)
			SETUP_FLAGS=(--optional)
			PKG_LABEL="Recommended + optional"
			;;
		*)
			SETUP_FLAGS=()
			PKG_LABEL="Recommended (default)"
			;;
	esac
	return 0
}

confirm_desktop() {
	wt --title "Confirm" --yesno \
		"Install Omaxian desktop for $(id -un)?\n\n\
Repo: $REPO_DIR\n\
Packages: $PKG_LABEL\n\n\
This will run (sudo for packages):\n\
  scripts/setup.sh\n\
  scripts/install.sh\n\
  scripts/deploy.sh\n\n\
You will be prompted for your password if needed." \
		16 72
}

# --- community plugins ------------------------------------------------------
# Sets SELECTED_PLUGIN_DIRS (basenames under community-plugins/)
SELECTED_PLUGIN_DIRS=()

ask_install_plugins() {
	wt --title "Community plugins" --yesno \
		"Install optional community plugins from this repo?\n\n\
They are NOT part of the default desktop. You can pick which ones next.\n\n\
Default: No." \
		12 72
}

choose_plugins() {
	local list args=() line dir id name tag
	SELECTED_PLUGIN_DIRS=()
	list=$("$PLUGIN_HELPER" --list) || true
	if [ -z "$list" ]; then
		wt --title "Community plugins" --msgbox "No community plugins found under community-plugins/." 8 60
		return 0
	fi

	# whiptail checklist: tag item status
	while IFS=$'\t' read -r dir id name; do
		[ -n "$dir" ] || continue
		# Tag must be unique and short enough; use directory name.
		args+=("$dir" "$name ($id)" OFF)
	done <<< "$list"

	if (( ${#args[@]} == 0 )); then
		return 0
	fi

	local selected
	selected=$(wt --title "Select community plugins" --checklist \
		"Space toggles. PulseAudio and PipeWire speaker calibrators are mutually exclusive — pick at most one." \
		20 78 12 \
		"${args[@]}" \
		3>&1 1>&2 2>&3) || return 1

	# whiptail returns quoted space-separated tags
	SELECTED_PLUGIN_DIRS=()
	local tok
	for tok in $selected; do
		tok=${tok//\"/}
		[ -n "$tok" ] || continue
		SELECTED_PLUGIN_DIRS+=("$tok")
	done

	# Enforce calibrator exclusivity
	local has_pulse=0 has_pipe=0
	for tok in "${SELECTED_PLUGIN_DIRS[@]+"${SELECTED_PLUGIN_DIRS[@]}"}"; do
		[[ $tok == omaxian-speaker-pulseaudio-calibrator ]] && has_pulse=1
		[[ $tok == omaxian-speaker-pipewire-calibrator ]] && has_pipe=1
	done
	if (( has_pulse && has_pipe )); then
		local pick
		pick=$(wt --title "Speaker calibrator" --radiolist \
			"Both audio calibrators were selected. Choose one audio stack:" \
			12 70 2 \
			pulse "PulseAudio calibrator" ON \
			pipewire "PipeWire calibrator" OFF \
			3>&1 1>&2 2>&3) || return 1
		local filtered=()
		for tok in "${SELECTED_PLUGIN_DIRS[@]}"; do
			if [[ $tok == omaxian-speaker-pulseaudio-calibrator || $tok == omaxian-speaker-pipewire-calibrator ]]; then
				continue
			fi
			filtered+=("$tok")
		done
		if [[ $pick == pipewire ]]; then
			filtered+=(omaxian-speaker-pipewire-calibrator)
		else
			filtered+=(omaxian-speaker-pulseaudio-calibrator)
		fi
		SELECTED_PLUGIN_DIRS=("${filtered[@]}")
	fi

	return 0
}

# Union apt packages for selected plugins; confirm; return 0 to proceed.
confirm_plugin_deps() {
	local pkgs=() manuals=() dir deps pkg note
	if (( ${#SELECTED_PLUGIN_DIRS[@]} == 0 )); then
		return 0
	fi
	for dir in "${SELECTED_PLUGIN_DIRS[@]}"; do
		deps="$REPO_DIR/community-plugins/$dir/omaxian.deps.json"
		[ -f "$deps" ] || continue
		while IFS= read -r pkg; do
			[ -n "$pkg" ] || continue
			pkgs+=("$pkg")
		done < <(jq -r '.apt // [] | .[]' "$deps" 2>/dev/null)
		while IFS= read -r note; do
			[ -n "$note" ] || continue
			manuals+=("$note")
		done < <(jq -r '.manual // [] | .[]' "$deps" 2>/dev/null)
	done

	mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]+"${pkgs[@]}"}" | sort -u)
	# Drop empties
	local need=()
	for pkg in "${pkgs[@]+"${pkgs[@]}"}"; do
		[ -n "$pkg" ] || continue
		if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
			continue
		fi
		need+=("$pkg")
	done

	local msg="Plugins to install:\n"
	local p
	for p in "${SELECTED_PLUGIN_DIRS[@]}"; do
		msg+="  • $p\n"
	done
	msg+="\n"
	if (( ${#need[@]} > 0 )); then
		msg+="apt packages to install (sudo):\n"
		for pkg in "${need[@]}"; do
			msg+="  • $pkg\n"
		done
	else
		msg+="No additional apt packages needed (already installed or none declared).\n"
	fi
	if (( ${#manuals[@]} > 0 )); then
		mapfile -t manuals < <(printf '%s\n' "${manuals[@]}" | sort -u)
		msg+="\nManual follow-up after install:\n"
		for note in "${manuals[@]}"; do
			msg+="  • $note\n"
		done
	fi
	msg+="\nContinue?"

	wt --title "Plugin dependencies" --yesno "$msg" 22 78
}

install_selected_plugins() {
	if (( ${#SELECTED_PLUGIN_DIRS[@]} == 0 )); then
		return 0
	fi
	phase_banner "Community plugins"
	"$PLUGIN_HELPER" "${SELECTED_PLUGIN_DIRS[@]}"
}

# --- main -------------------------------------------------------------------
run_desktop() {
	phase_banner "1/3  System packages (setup.sh)"
	sudo "$SETUP" "${SETUP_FLAGS[@]+"${SETUP_FLAGS[@]}"}"

	phase_banner "2/3  Themes and commands (install.sh)"
	"$INSTALL"

	phase_banner "3/3  Home configs (deploy.sh)"
	"$DEPLOY"
}

final_checklist() {
	local extra="${1:-}"
	local text
	text="Omaxian install finished.\n\n\
Next steps:\n\
  1. Log out and log back in (full login, not i3 restart).\n\
  2. Pick the i3 / Omaxian session in your greeter.\n\
  3. Smoke-check:\n\
       omarchy-shell shell ping\n\
       omarchy-shell shell listPlugins | jq length\n\
       pgrep -x quickshell\n"
	if [ -n "$extra" ]; then
		text+="\n$extra"
	fi
	if (( NONINTERACTIVE )); then
		echo
		echo "========================================================================"
		echo -e "$text"
		echo "========================================================================"
	else
		wt --title "Done" --msgbox "$(echo -e "$text")" 20 72 || true
	fi
}

main_interactive() {
	ensure_whiptail

	wt --title "Welcome" --msgbox \
		"Omaxian — Omarchy for Devuan/Debian + X11 + i3.\n\n\
This installer will:\n\
  • install system packages (sudo)\n\
  • seed themes and omarchy-* commands\n\
  • deploy i3 / Quickshell / ~/.xsessionrc\n\
  • optionally install community plugins\n\n\
Repo: $REPO_DIR" \
		16 72 || exit 1

	choose_package_set || { echo ":: cancelled"; exit 1; }
	confirm_desktop || { echo ":: cancelled"; exit 1; }

	run_desktop

	local plugin_extra=""
	if ask_install_plugins; then
		choose_plugins || { echo ":: plugin selection cancelled — desktop is installed"; final_checklist; exit 0; }
		if (( ${#SELECTED_PLUGIN_DIRS[@]} > 0 )); then
			confirm_plugin_deps || { echo ":: plugin deps declined — desktop is installed"; final_checklist; exit 0; }
			install_selected_plugins
			plugin_extra="Community plugins were copied to ~/.config/omarchy/plugins/.\nEnable any that were not auto-enabled under Settings → Plugins after login."
		fi
	fi

	final_checklist "$plugin_extra"
}

main_noninteractive() {
	SETUP_FLAGS=()
	PKG_LABEL="Recommended (default)"
	echo ":: noninteractive: recommended packages + install + deploy (no community plugins)"
	run_desktop
	final_checklist "Community plugins were skipped (--yes). Run ./omaxian-install.sh later or see community-plugins/README.md."
}

if (( NONINTERACTIVE )); then
	main_noninteractive
else
	main_interactive
fi
