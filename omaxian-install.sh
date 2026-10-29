#!/bin/bash
# omaxian-install.sh — one-shot TUI installer for Omaxian (Devuan/Debian + X11 + i3).
#
# Orchestrates scripts/setup.sh → install.sh → deploy.sh, then optionally
# community plugins (with apt deps from omaxian.deps.json).
#
#   ./omaxian-install.sh
#   ./omaxian-install.sh --yes          # noninteractive: recommended + deploy, no plugins
#   OMAXIAN_INSTALL_NONINTERACTIVE=1 ./omaxian-install.sh
#   ./omaxian-install.sh --version
#
# Version comes from the repo-root `version` file (same as the release).
# Remote first-time: curl -fsSL …/bootstrap.sh | bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$REPO_DIR/scripts"
SETUP="$SCRIPTS/setup.sh"
INSTALL="$SCRIPTS/install.sh"
DEPLOY="$SCRIPTS/deploy.sh"
PLUGIN_HELPER="$SCRIPTS/install-community-plugins.sh"
# shellcheck source=scripts/lib/ui.sh
source "$SCRIPTS/lib/ui.sh"

# Release version from repo root (e.g. v1.0.3). Shown in TUI backtitle chrome.
OMAXIAN_VERSION="unknown"
if [ -f "$REPO_DIR/version" ]; then
	OMAXIAN_VERSION=$(tr -d '[:space:]' <"$REPO_DIR/version")
	[[ -n $OMAXIAN_VERSION ]] || OMAXIAN_VERSION="unknown"
fi
# Whiptail/dialog put --backtitle on the top screen edge (left); that is the
# only reliable "chrome" corner for version text.
TUI_BACKTITLE="Omaxian installer  ${OMAXIAN_VERSION}"

NONINTERACTIVE=0
for arg in "$@"; do
	case "$arg" in
		--yes|-y)  NONINTERACTIVE=1 ;;
		-V|--version)
			echo "omaxian-install ${OMAXIAN_VERSION}"
			exit 0
			;;
		-h|--help)
			sed -n '2,18p' "$0"
			echo
			echo "omaxian-install ${OMAXIAN_VERSION}"
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
		omaxian_err "refuse to install as root — run:  ./omaxian-install.sh"
		exit 1
	fi
	omaxian_msg "re-exec as $SUDO_USER (was root via sudo)"
	exec sudo -u "$SUDO_USER" -H "$0" "$@"
fi

for f in "$SETUP" "$INSTALL" "$DEPLOY" "$PLUGIN_HELPER"; do
	if [ ! -x "$f" ]; then
		omaxian_err "missing $f — wrong checkout?"
		exit 1
	fi
done

# --- TUI helpers (whiptail menus; dialog for live command output) -----------
# Whiptail has no programbox. dialog --programbox keeps apt/setup "inside" the
# TUI instead of dropping to a bare terminal after each menu.
wt() {
	whiptail --backtitle "$TUI_BACKTITLE" "$@"
}

phase_banner() {
	omaxian_phase "$1"
}

# Cache sudo via a whiptail password box so apt never steals the TTY mid-flow.
ensure_sudo() {
	if sudo -n true 2>/dev/null; then
		return 0
	fi
	if (( NONINTERACTIVE )); then
		# May prompt on the terminal once; credential stays cached for setup.
		sudo -v || {
			omaxian_err "sudo is required for package install"
			exit 1
		}
		return 0
	fi
	local pass tries=0
	while (( tries < 3 )); do
		pass=$(wt --title "sudo password" --passwordbox \
			"Omaxian needs administrator privileges to install packages.\n\nEnter your password for sudo:" \
			11 70 3>&1 1>&2 2>&3) || {
			omaxian_msg "cancelled (sudo)"
			exit 1
		}
		if printf '%s\n' "$pass" | sudo -S -v >/dev/null 2>&1; then
			unset pass
			# Keep the ticket alive for long apt runs.
			sudo -v
			return 0
		fi
		unset pass
		tries=$((tries + 1))
		wt --title "sudo password" --msgbox "Incorrect password. Try again ($tries/3)." 8 50 || true
	done
	omaxian_err "sudo authentication failed"
	exit 1
}

ensure_tui_tools() {
	local need=()
	command -v whiptail >/dev/null 2>&1 || need+=(whiptail)
	# dialog --programbox streams setup/apt without leaving the TUI chrome.
	command -v dialog >/dev/null 2>&1 || need+=(dialog)
	if (( ${#need[@]} == 0 )); then
		return 0
	fi
	omaxian_msg "installing TUI tools: ${need[*]}"
	if ! sudo -n true 2>/dev/null; then
		# No whiptail yet → must prompt on the terminal this one time.
		if ! command -v whiptail >/dev/null 2>&1; then
			sudo apt-get install -y "${need[@]}" || {
				omaxian_err "install whiptail (and dialog) then re-run: sudo apt install whiptail dialog"
				exit 1
			}
			return 0
		fi
		ensure_sudo
	fi
	sudo apt-get install -y "${need[@]}" || {
		omaxian_err "could not install: ${need[*]}"
		exit 1
	}
}

# Run a long phase; in interactive mode stream stdout/stderr into dialog.
# Children see OMAXIAN_NESTED=1 so they skip a second ASCII banner.
run_phase() {
	local title="$1"
	shift
	if (( NONINTERACTIVE )) || ! command -v dialog >/dev/null 2>&1; then
		phase_banner "$title"
		OMAXIAN_NESTED=1 "$@"
		return
	fi
	local ec=0
	set +e
	set -o pipefail
	OMAXIAN_NESTED=1 "$@" 2>&1 | dialog --backtitle "$TUI_BACKTITLE" --title "$title" --programbox 22 84
	ec=${PIPESTATUS[0]}
	set +o pipefail
	set -e
	if (( ec != 0 )); then
		wt --title "Phase failed" --msgbox \
			"$title exited with status $ec.\n\nFix the error above (scroll the previous box if needed) and re-run ./omaxian-install.sh." \
			12 70 || true
		exit "$ec"
	fi
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
This will run:\n\
  scripts/setup.sh   (apt — sudo password via this TUI)\n\
  scripts/install.sh\n\
  scripts/deploy.sh\n\n\
Package output stays in a dialog window (not a bare shell)." \
		17 72
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

# Short checklist tag (left column) — directory names like
# omaxian-speaker-pulseaudio-calibrator overflow a ~78-col whiptail box.
plugin_checklist_tag() {
	local dir="$1"
	case "$dir" in
		omaxian-speaker-pulseaudio-calibrator) echo "spk-pulse" ;;
		omaxian-speaker-pipewire-calibrator)   echo "spk-pipe" ;;
		*.*) echo "${dir##*.}" ;;
		*)   echo "$dir" ;;
	esac
}

# Short friendly label (right column) — name only, not "Name (long.id)".
plugin_checklist_label() {
	local dir="$1" name="$2"
	case "$dir" in
		omaxian-speaker-pulseaudio-calibrator) echo "Speaker (Pulse)" ;;
		omaxian-speaker-pipewire-calibrator)   echo "Speaker (PipeWire)" ;;
		*) echo "$name" ;;
	esac
}

choose_plugins() {
	local list args=() dir id name tag label
	local -A tag_to_dir=()
	SELECTED_PLUGIN_DIRS=()
	list=$("$PLUGIN_HELPER" --list) || true
	if [ -z "$list" ]; then
		wt --title "Community plugins" --msgbox "No community plugins found under community-plugins/." 8 60
		return 0
	fi

	# whiptail checklist: short tag + short label (avoids TUI overflow)
	while IFS=$'\t' read -r dir id name; do
		[ -n "$dir" ] || continue
		tag=$(plugin_checklist_tag "$dir")
		label=$(plugin_checklist_label "$dir" "$name")
		tag_to_dir[$tag]=$dir
		args+=("$tag" "$label" OFF)
	done <<< "$list"

	if (( ${#args[@]} == 0 )); then
		return 0
	fi

	local selected
	selected=$(wt --title "Select community plugins" --checklist \
		"Space toggles. Speaker calibrators are mutually exclusive — pick at most one." \
		20 60 12 \
		"${args[@]}" \
		3>&1 1>&2 2>&3) || return 1

	# whiptail returns quoted space-separated tags
	SELECTED_PLUGIN_DIRS=()
	local tok
	for tok in $selected; do
		tok=${tok//\"/}
		[ -n "$tok" ] || continue
		SELECTED_PLUGIN_DIRS+=("${tag_to_dir[$tok]}")
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
			12 60 2 \
			pulse "PulseAudio" ON \
			pipewire "PipeWire" OFF \
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

	local msg="Plugins:\n"
	local p pname
	for p in "${SELECTED_PLUGIN_DIRS[@]}"; do
		pname=$(jq -r '.name // .id' "$REPO_DIR/community-plugins/$p/manifest.json" 2>/dev/null) || pname="$p"
		msg+="  • $(plugin_checklist_label "$p" "$pname")\n"
	done
	msg+="\n"
	if (( ${#need[@]} > 0 )); then
		msg+="apt packages (sudo):\n"
		for pkg in "${need[@]}"; do
			msg+="  • $pkg\n"
		done
	else
		msg+="No extra apt packages needed.\n"
	fi
	if (( ${#manuals[@]} > 0 )); then
		mapfile -t manuals < <(printf '%s\n' "${manuals[@]}" | sort -u)
		msg+="\nManual follow-up:\n"
		for note in "${manuals[@]}"; do
			msg+="  • $note\n"
		done
	fi
	msg+="\nContinue?"

	wt --title "Plugin dependencies" --yesno "$msg" 20 64
}

install_selected_plugins() {
	if (( ${#SELECTED_PLUGIN_DIRS[@]} == 0 )); then
		return 0
	fi
	ensure_sudo
	run_phase "Community plugins" "$PLUGIN_HELPER" "${SELECTED_PLUGIN_DIRS[@]}"
}

# --- Quickshell (required for the bar) --------------------------------------
QUICKSHELL_MISSING=0

quickshell_present() {
	command -v quickshell >/dev/null 2>&1
}

quickshell_in_apt() {
	apt-cache show quickshell >/dev/null 2>&1
}

# Rough distro hint for README-aligned install instructions.
distro_hint() {
	local id="" version_id=""
	# shellcheck disable=SC1091
	if [ -r /etc/os-release ]; then
		. /etc/os-release
		id="${ID:-}"
		version_id="${VERSION_ID:-}"
	fi
	case "$id" in
		devuan) echo "devuan" ;;
		debian)
			# 13 = trixie; testing pin is often needed there.
			if [[ ${version_id%%.*} == 13 ]]; then
				echo "debian13"
			else
				echo "debian"
			fi
			;;
		ubuntu) echo "ubuntu" ;;
		*)      echo "other" ;;
	esac
}

quickshell_instructions_text() {
	local hint
	hint=$(distro_hint)
	local text
	text="Quickshell is required for the Omaxian bar (≥ 0.2; 0.3.x tested).\n\
It was not found on PATH after setup.\n\n"

	if quickshell_in_apt; then
		text+="This suite has a 'quickshell' package. Install with:\n\n\
  sudo apt install quickshell\n\n\
Then re-run this check or log out and back in.\n"
	else
		case "$hint" in
			debian13)
				text+="On Debian 13, Quickshell is usually only in testing (Forky).\n\
Pin Forky at priority 100, then:\n\n\
  sudo apt update\n\
  sudo apt install -t forky quickshell \\\n\
    qml6-module-qtquick-layouts \\\n\
    qml6-module-qtquick-controls \\\n\
    qml6-module-qtquick-shapes \\\n\
    qml6-module-qt-labs-folderlistmodel \\\n\
    qml6-module-qtquick-effects\n\n\
Full pinning steps: README.md → \"Debian 13 and Devuan Excalibur\".\n"
				;;
			devuan)
				text+="On Devuan Excalibur, Quickshell is usually only in testing (Freia).\n\
Pin Freia at priority 100, then:\n\n\
  sudo apt update\n\
  sudo apt install -t freia quickshell \\\n\
    qml6-module-qtquick-layouts \\\n\
    qml6-module-qtquick-controls \\\n\
    qml6-module-qtquick-shapes \\\n\
    qml6-module-qt-labs-folderlistmodel \\\n\
    qml6-module-qtquick-effects\n\n\
Full pinning steps: README.md → \"Debian 13 and Devuan Excalibur\".\n"
				;;
			ubuntu)
				text+="On Ubuntu, follow the Quickshell Ubuntu guide:\n\
  https://quickshell.org/docs/v0.3.0/guide/install-setup/#ubuntu\n\n\
(Omaxian needs X11 — e.g. Xubuntu / xubuntu-desktop; see README \"Ubuntu 26\".)\n"
				;;
			*)
				text+="This suite has no 'quickshell' package in default apt.\n\
Build from source:\n\
  https://quickshell.org/docs/guide/install/\n\n\
Or use testing-repo pinning (Debian Forky / Devuan Freia) as documented in\n\
README.md → \"Debian 13 and Devuan Excalibur\" / \"Quickshell\".\n"
				;;
		esac
	fi

	text+="\nWithout Quickshell the bar will not start."
	printf '%s' "$text"
}

# After desktop phases: confirm Quickshell or show install instructions.
check_quickshell() {
	if quickshell_present; then
		QUICKSHELL_MISSING=0
		local ver
		ver=$(quickshell --version 2>/dev/null | head -n1 || echo "found on PATH")
		omaxian_msg "Quickshell OK ($ver)"
		if (( ! NONINTERACTIVE )); then
			wt --title "Quickshell" --msgbox \
				"Quickshell is installed ($ver).\n\nThe bar can start after you log into an i3 / Omaxian session." \
				10 64 || true
		fi
		return 0
	fi

	QUICKSHELL_MISSING=1
	local text
	text=$(quickshell_instructions_text)
	echo
	omaxian_err "Quickshell missing"
	echo -e "$text"

	if (( NONINTERACTIVE )); then
		return 0
	fi

	wt --title "Quickshell required" --msgbox "$(echo -e "$text")" 22 72 || true
}

# --- main -------------------------------------------------------------------
start_sudo_keepalive() {
	(
		while true; do
			sleep 50
			sudo -n true 2>/dev/null || exit 0
		done
	) &
	SUDO_KEEPALIVE_PID=$!
}

stop_sudo_keepalive() {
	if [[ -n ${SUDO_KEEPALIVE_PID:-} ]]; then
		kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
		wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
		unset SUDO_KEEPALIVE_PID
	fi
}

run_desktop() {
	ensure_sudo
	start_sudo_keepalive
	trap stop_sudo_keepalive EXIT
	# setup.sh re-execs as root; pass OMAXIAN_NESTED through sudo's env reset.
	run_phase "1/3  System packages (setup.sh)" \
		sudo -n env OMAXIAN_NESTED=1 "$SETUP" "${SETUP_FLAGS[@]+"${SETUP_FLAGS[@]}"}"

	run_phase "2/3  Themes and commands (install.sh)" "$INSTALL"

	run_phase "3/3  Home configs (deploy.sh)" "$DEPLOY"
	stop_sudo_keepalive
	trap - EXIT
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
	if (( QUICKSHELL_MISSING )); then
		text+="\n!! Quickshell is not installed yet — the bar will not start.\n\
   See README.md (Quickshell / Debian 13 and Devuan Excalibur),\n\
   or re-run ./omaxian-install.sh after installing it.\n"
	fi
	if [ -n "$extra" ]; then
		text+="\n$extra"
	fi
	if (( NONINTERACTIVE )); then
		echo
		omaxian_done "install finished"
		echo -e "$text"
	else
		wt --title "Done" --msgbox "$(echo -e "$text")" 20 68 || true
	fi
}

main_interactive() {
	omaxian_banner
	omaxian_msg "installer ${OMAXIAN_VERSION}"
	ensure_tui_tools

	wt --title "Welcome" --msgbox \
		"Omaxian ${OMAXIAN_VERSION}\n\
Omarchy for Devuan/Debian + X11 + i3.\n\n\
This installer will:\n\
  • install system packages (sudo)\n\
  • seed themes and omarchy-* commands\n\
  • deploy i3 / Quickshell configs\n\
  • verify Quickshell (required for the bar)\n\
  • optionally install community plugins\n\n\
Repo: $REPO_DIR" \
		17 64 || exit 1

	choose_package_set || { omaxian_msg "cancelled"; exit 1; }
	confirm_desktop || { omaxian_msg "cancelled"; exit 1; }

	run_desktop
	check_quickshell

	local plugin_extra=""
	if ask_install_plugins; then
		choose_plugins || { omaxian_msg "plugin selection cancelled — desktop is installed"; final_checklist; exit 0; }
		if (( ${#SELECTED_PLUGIN_DIRS[@]} > 0 )); then
			confirm_plugin_deps || { omaxian_msg "plugin deps declined — desktop is installed"; final_checklist; exit 0; }
			install_selected_plugins
			plugin_extra="Community plugins → ~/.config/omarchy/plugins/.\nEnable under Settings → Plugins after login if needed."
		fi
	fi

	final_checklist "$plugin_extra"
}

main_noninteractive() {
	SETUP_FLAGS=()
	PKG_LABEL="Recommended (default)"
	omaxian_banner
	omaxian_msg "installer ${OMAXIAN_VERSION}  (noninteractive)"
	omaxian_info "recommended packages + install + deploy (no community plugins)"
	run_desktop
	check_quickshell
	final_checklist "Community plugins skipped (--yes). Re-run ./omaxian-install.sh or see community-plugins/README.md."
}

if (( NONINTERACTIVE )); then
	main_noninteractive
else
	main_interactive
fi
