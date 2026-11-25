#!/bin/bash
# omaxian-install.sh — one-shot TUI installer for Omaxian (Devuan/Debian + X11 + i3).
#
# Orchestrates scripts/setup.sh → install.sh → deploy.sh, then optionally
# community plugins and community apps (with apt deps from omaxian.deps.json).
#
#   ./omaxian-install.sh
#   ./omaxian-install.sh --yes          # noninteractive: recommended + deploy, no plugins/apps
#   OMAXIAN_INSTALL_NONINTERACTIVE=1 ./omaxian-install.sh
#   ./omaxian-install.sh --version
#
# Version comes from the repo-root `version` file (same as the release).
# Remote first-time: curl -fsSL …/bootstrap.sh | bash
# Every phase's output is saved to ~/.cache/omaxian/install-<timestamp>.log.

# Box sizes come from $(fit H W) and are split on purpose ("rows cols").
# shellcheck disable=SC2046

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$REPO_DIR/scripts"
SETUP="$SCRIPTS/setup.sh"
INSTALL="$SCRIPTS/install.sh"
DEPLOY="$SCRIPTS/deploy.sh"
PLUGIN_HELPER="$SCRIPTS/install-community-plugins.sh"
APP_HELPER="$SCRIPTS/install-community-apps.sh"
# shellcheck source=scripts/lib/ui.sh
source "$SCRIPTS/lib/ui.sh"

# Release version from repo root (e.g. v1.0.3). Shown in TUI backtitle chrome.
OMAXIAN_VERSION="unknown"
if [[ -f $REPO_DIR/version ]]; then
	OMAXIAN_VERSION=$(tr -d '[:space:]' <"$REPO_DIR/version")
	[[ -n $OMAXIAN_VERSION ]] || OMAXIAN_VERSION="unknown"
fi
# Whiptail/dialog put --backtitle on the top screen edge (left); that is the
# only reliable "chrome" corner for version text.
TUI_BACKTITLE="Omaxian installer  ${OMAXIAN_VERSION}"

# Print the leading comment block of this file (usage), without the "# ".
print_usage() {
	awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

NONINTERACTIVE=0
for arg in "$@"; do
	case "$arg" in
		--yes|-y)  NONINTERACTIVE=1 ;;
		-V|--version)
			echo "omaxian-install ${OMAXIAN_VERSION}"
			exit 0
			;;
		-h|--help)
			print_usage
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
if [[ ${OMAXIAN_INSTALL_NONINTERACTIVE:-0} == "1" ]]; then
	NONINTERACTIVE=1
fi

# --- privilege: never seed /root --------------------------------------------
if (( $(id -u) == 0 )); then
	if [[ -z ${SUDO_USER:-} || $SUDO_USER == "root" ]]; then
		omaxian_err "refuse to install as root — run:  ./omaxian-install.sh"
		exit 1
	fi
	omaxian_msg "re-exec as $SUDO_USER (was root via sudo)"
	exec sudo -u "$SUDO_USER" -H "$0" "$@"
fi

for f in "$SETUP" "$INSTALL" "$DEPLOY" "$PLUGIN_HELPER" "$APP_HELPER"; do
	if [[ ! -x $f ]]; then
		omaxian_err "missing $f — wrong checkout?"
		exit 1
	fi
done

# --- install log ------------------------------------------------------------
# dialog --programbox only shows the last lines and vanishes when closed, so
# every phase is also appended here. The sudo password never reaches it.
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omaxian"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
{
	echo "omaxian-install ${OMAXIAN_VERSION}  $(date -Is)"
	echo "repo $REPO_DIR"
} >"$LOG_FILE"

log_section() {
	printf '\n== %s  (%s)\n' "$1" "$(date -Is)" >>"$LOG_FILE"
}

# --- cleanup ----------------------------------------------------------------
SUDO_KEEPALIVE_PID=""

stop_sudo_keepalive() {
	if [[ -n $SUDO_KEEPALIVE_PID ]]; then
		kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
		wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
		SUDO_KEEPALIVE_PID=""
	fi
}

trap stop_sudo_keepalive EXIT

# Refresh the sudo ticket until this script exits. Community app builds can
# outlast sudo's 15-minute default; an expired ticket makes the next app's
# `sudo apt-get` prompt behind the dialog window, which looks like a hang.
start_sudo_keepalive() {
	[[ -z $SUDO_KEEPALIVE_PID ]] || return 0
	(
		while sleep 50; do
			sudo -n -v 2>/dev/null || exit 0
		done
	) &
	SUDO_KEEPALIVE_PID=$!
}

# --- TUI helpers (whiptail menus; dialog for live command output) -----------
# Whiptail has no programbox. dialog --programbox keeps apt/setup "inside" the
# TUI instead of dropping to a bare terminal after each menu.
wt() {
	whiptail --backtitle "$TUI_BACKTITLE" "$@"
}

# Print "rows cols" for the controlling terminal (fallback 24×80).
term_size() {
	local size
	size=$(stty size 2>/dev/null </dev/tty) || size=""
	if [[ ! $size =~ ^[0-9]+\ [0-9]+$ ]]; then
		size="${LINES:-24} ${COLUMNS:-80}"
	fi
	echo "$size"
}

# fit H W → "h w" clamped to the terminal, so an 80×25 console still fits.
fit() {
	local rows cols h=$1 w=$2
	read -r rows cols < <(term_size)
	if (( h > rows - 2 )); then h=$(( rows - 2 )); fi
	if (( w > cols - 2 )); then w=$(( cols - 2 )); fi
	echo "$h $w"
}

phase_banner() {
	omaxian_phase "$1"
}

# --- preflight ----------------------------------------------------------------
# Hard requirements abort; anything else becomes a warning shown on the
# Welcome screen (or printed with --yes).
PREFLIGHT_WARNINGS=()

os_release_field() {
	local field="$1"
	[[ -r /etc/os-release ]] || return 0
	# Subshell: do not leak ID / NAME / VERSION into this script.
	(
		# shellcheck disable=SC1091
		. /etc/os-release
		printf '%s\n' "${!field:-}"
	)
}

preflight() {
	local tool
	for tool in apt-get apt-cache dpkg-query sudo; do
		if ! command -v "$tool" >/dev/null 2>&1; then
			omaxian_err "$tool not found — Omaxian needs a Debian-family system (Devuan, Debian, Ubuntu)"
			exit 1
		fi
	done

	local id id_like
	id=$(os_release_field ID)
	id_like=$(os_release_field ID_LIKE)
	if [[ " $id $id_like " != *" debian "* && " $id $id_like " != *" ubuntu "* && $id != "devuan" ]]; then
		PREFLIGHT_WARNINGS+=("Untested distribution (${id:-unknown}). Omaxian targets Devuan / Debian.")
	fi

	# Desktop + upstream clone + fonts need ~1 GB; app builds need several more.
	local free_kb
	free_kb=$(df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 { print $4 }')
	if [[ $free_kb =~ ^[0-9]+$ ]] && (( free_kb < 3 * 1024 * 1024 )); then
		PREFLIGHT_WARNINGS+=("Less than 3 GB free in $HOME ($(( free_kb / 1024 )) MB). Community app builds need more.")
	fi

	# setup.sh clones upstream Omarchy from GitHub.
	if ! getent hosts github.com >/dev/null 2>&1; then
		PREFLIGHT_WARNINGS+=("Cannot resolve github.com. setup.sh clones upstream Omarchy from GitHub.")
	fi
}

# Cache sudo via a whiptail password box so apt never steals the TTY mid-flow.
# Falls back to a terminal prompt with --yes or before whiptail is installed.
ensure_sudo() {
	if sudo -n true 2>/dev/null; then
		start_sudo_keepalive
		return 0
	fi
	if (( NONINTERACTIVE )) || ! command -v whiptail >/dev/null 2>&1; then
		sudo -v || {
			omaxian_err "sudo is required for package install"
			exit 1
		}
		start_sudo_keepalive
		return 0
	fi
	local pass tries=0
	while (( tries < 3 )); do
		pass=$(wt --title "sudo password" --passwordbox \
			"Omaxian needs administrator privileges to install packages.\n\nEnter your password for sudo:" \
			$(fit 11 70) 3>&1 1>&2 2>&3) || {
			omaxian_msg "cancelled (sudo)"
			exit 1
		}
		if printf '%s\n' "$pass" | sudo -S -v >/dev/null 2>&1; then
			unset pass
			start_sudo_keepalive
			return 0
		fi
		unset pass
		tries=$(( tries + 1 ))
		wt --title "sudo password" --msgbox "Incorrect password. Try again ($tries/3)." $(fit 8 50) || true
	done
	omaxian_err "sudo authentication failed"
	exit 1
}

# Install the few tools this installer needs before setup.sh runs. Only
# refreshes apt (and only asks for sudo) when something is actually missing;
# setup.sh runs its own apt update for the desktop packages.
#   ensure_preflight_tools whiptail dialog git
ensure_preflight_tools() {
	local need=() tool
	for tool in "$@"; do
		command -v "$tool" >/dev/null 2>&1 || need+=("$tool")
	done
	if (( ${#need[@]} == 0 )); then
		return 0
	fi

	omaxian_msg "the installer needs: ${need[*]}"
	if (( ! NONINTERACTIVE )); then
		local reply=""
		read -r -p "   Install them now with sudo apt-get? [Y/n] " reply </dev/tty || reply="n"
		if [[ $reply == [nN]* ]]; then
			omaxian_err "cancelled — install them yourself: sudo apt install ${need[*]}"
			exit 1
		fi
	fi
	ensure_sudo
	# Terminal spinner (omaxian_spin); sudo -n: the ticket is fresh, and a
	# prompt would be hidden behind the spinner.
	omaxian_spin "apt update" sudo -n apt-get update || {
		omaxian_err "apt update failed — check network / sources and re-run"
		exit 1
	}
	omaxian_spin "installing ${need[*]}" \
		sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y "${need[@]}" || {
		omaxian_err "could not install: ${need[*]}"
		exit 1
	}
}

# --- phase runner ---------------------------------------------------------------
# True when phases are drawn in the TUI (spinner gauge) rather than streamed
# to the terminal.
tui_phases() {
	(( ! NONINTERACTIVE )) && command -v dialog >/dev/null 2>&1
}

# Kill a process and its descendants. Root-owned children (apt under sudo)
# refuse the signal; sudo forwards it to them when it is killed.
kill_tree() {
	local child
	for child in $(pgrep -P "$1" 2>/dev/null); do
		kill_tree "$child"
	done
	kill -TERM "$1" 2>/dev/null || true
}

# Strip colour codes and carriage-return redraws (cargo, apt progress) so
# only the final text of each line is shown.
clean_output() {
	sed -u -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' -e 's/.*\r//'
}

# Read new phase output and print the current state as three lines:
#   section  (latest "-- label" line; "-- i/N label" also sets progress)
#   step     (latest ":: msg", ">> msg", or "   label ..." line)
#   progress (per mille within the phase, from the latest "-- i/N")
# Previous state comes in through PHASE_SEC / PHASE_STEP / PHASE_PERMILLE.
parse_phase_state() {
	awk '
		BEGIN {
			sec = ENVIRON["PHASE_SEC"]; step = ENVIRON["PHASE_STEP"]
			pm = ENVIRON["PHASE_PERMILLE"] + 0
		}
		/^-- / {
			s = substr($0, 4)
			if (match(s, /^[0-9]+\/[0-9]+/)) {
				split(substr(s, 1, RLENGTH), a, "/")
				if (a[2] > 0) pm = int((a[1] - 1) * 1000 / a[2])
				s = substr(s, RLENGTH + 1)
			}
			sub(/^ +/, "", s)
			sec = s; step = ""
			next
		}
		/^(:: |>> )/ { step = substr($0, 4); next }
		/^   [^ .].* \.\.\.$/ { step = substr($0, 4); sub(/ \.\.\.$/, "", step); next }
		END { print sec; print step; print pm }
	'
}

TUI_SPIN_FRAMES=('[=    ]' '[ =   ]' '[  =  ]' '[   = ]' '[    =]' '[   = ]' '[  =  ]' '[ =   ]')

# Send one update from stdin to the gauge without blocking. dialog can stop
# reading (seen after rapid terminal resizes); a blocking write would then
# freeze the installer. With the pipe full, the update is dropped.
#   gauge_send <fd>
gauge_send() {
	dd bs=65536 iflag=fullblock oflag=nonblock status=none >&"$1" 2>/dev/null || true
}

# Close the gauge pipe and wait for dialog to exit on EOF. A stalled dialog
# never gets there, so kill it and restore the terminal.
#   gauge_close <fd> <dialog pid>
gauge_close() {
	local fd="$1" pid="$2" sig _
	exec {fd}>&-
	for sig in TERM KILL; do
		for _ in $(seq 1 20); do
			kill -0 "$pid" 2>/dev/null || break 2
			sleep 0.1
		done
		kill -"$sig" "$pid" 2>/dev/null || true
		stty sane 2>/dev/null </dev/tty || true
	done
	wait "$pid" 2>/dev/null || true
}

# Draw a phase as a dialog gauge that updates in place: a spinner, the
# current step label, elapsed time, overall progress, and the last lines of
# output. The command's output goes to $LOG_FILE only.
#   run_phase_tui <title> <pct from> <pct to> <command> [args…]
run_phase_tui() {
	local title="$1" from="$2" to="$3"
	shift 3
	local h w tail_n text_w fifo gfd gpid pid ec=0 start_off off size tick=0 t0=$SECONDS
	local label pct el msg line window_off
	local -a state=() lines=()
	local PHASE_SEC="" PHASE_STEP="" PHASE_PERMILLE=0
	export PHASE_SEC PHASE_STEP PHASE_PERMILLE

	read -r h w < <(fit 20 80)
	tail_n=$(( h - 8 ))
	if (( tail_n < 1 )); then tail_n=1; fi
	text_w=$(( w - 4 ))
	start_off=$(stat -c %s "$LOG_FILE")
	off=$start_off

	fifo=$(mktemp -u "${TMPDIR:-/tmp}/omaxian-gauge.XXXXXX")
	mkfifo -m 600 "$fifo"
	dialog --backtitle "$TUI_BACKTITLE" --title "$title" --no-collapse \
		--gauge "Starting…" "$h" "$w" "$from" <"$fifo" &
	gpid=$!
	exec {gfd}>"$fifo"
	rm -f -- "$fifo"

	# The phase must not inherit the gauge pipe: a daemon it leaves running
	# (deploy.sh restarts picom) would keep it open, and dialog never gets EOF.
	OMAXIAN_NESTED=1 OMAXIAN_TUI_SPINNER=1 "$@" >>"$LOG_FILE" 2>&1 </dev/null {gfd}>&- &
	pid=$!

	# Ctrl-C: background jobs ignore SIGINT, so stop the phase explicitly.
	# shellcheck disable=SC2064
	trap "kill_tree $pid; gauge_close $gfd $gpid; clear; omaxian_err 'interrupted'; exit 130" INT TERM
	# If dialog dies (tiny terminal), keep running instead of dying on SIGPIPE.
	trap '' PIPE

	while kill -0 "$pid" 2>/dev/null; do
		size=$(stat -c %s "$LOG_FILE")
		if (( size > off )); then
			mapfile -t state < <(tail -c +$(( off + 1 )) "$LOG_FILE" | head -c $(( size - off )) \
				| clean_output | parse_phase_state)
			PHASE_SEC=${state[0]-}
			PHASE_STEP=${state[1]-}
			PHASE_PERMILLE=${state[2]-0}
			window_off=$start_off
			if (( size - start_off > 16384 )); then window_off=$(( size - 16384 )); fi
			mapfile -t lines < <(tail -c +$(( window_off + 1 )) "$LOG_FILE" | clean_output \
				| grep -v '^[[:space:]]*$' | tail -n "$tail_n")
			off=$size
		fi

		label=${PHASE_SEC:-$title}
		if [[ -n $PHASE_STEP ]]; then label+=" — $PHASE_STEP"; fi
		el=$(( SECONDS - t0 ))
		pct=$(( from + (to - from) * PHASE_PERMILLE / 1000 ))
		msg=$(printf '%s  %s  (%d:%02d)' "${TUI_SPIN_FRAMES[tick % ${#TUI_SPIN_FRAMES[@]}]}" \
			"$label" $(( el / 60 )) $(( el % 60 )))
		msg="${msg:0:text_w}\\n"
		for line in "${lines[@]+"${lines[@]}"}"; do
			line=${line:0:text_w}
			# dialog expands "\n"; keep other backslashes from forming escapes.
			msg+="\\n${line//\\//}"
		done
		printf 'XXX\n%d\n%s\nXXX\n' "$pct" "$msg" | gauge_send "$gfd"
		tick=$(( tick + 1 ))
		sleep 0.2
	done
	wait "$pid" || ec=$?

	gauge_close "$gfd" "$gpid"
	trap - INT TERM PIPE
	return "$ec"
}

# Run a long phase. Interactive: a spinner gauge (run_phase_tui). --yes or no
# dialog: stream to the terminal. Output always goes to $LOG_FILE.
# Children see OMAXIAN_NESTED=1 so they skip a second ASCII banner.
#   run_phase [--soft] [--pct FROM TO] <title> <command> [args…]
# --soft: report a failure and return its status instead of exiting.
# --pct:  where the gauge's bar starts and ends for this phase (default 0 100).
run_phase() {
	local soft=0 from=0 to=100
	while [[ $1 == --* ]]; do
		case "$1" in
			--soft) soft=1; shift ;;
			--pct)  from=$2; to=$3; shift 3 ;;
			*) break ;;
		esac
	done
	local title="$1" ec=0 tail_text
	shift
	log_section "$title"
	if tui_phases; then
		run_phase_tui "$title" "$from" "$to" "$@" || ec=$?
	else
		phase_banner "$title"
		set +e
		OMAXIAN_NESTED=1 "$@" 2>&1 | tee -a "$LOG_FILE"
		ec=${PIPESTATUS[0]}
		set -e
	fi
	if (( ec == 0 )); then
		return 0
	fi

	tail_text=$(tail -n 10 "$LOG_FILE" | clean_output)
	echo "!! $title exited with status $ec" >>"$LOG_FILE"
	if (( NONINTERACTIVE )); then
		omaxian_err "$title failed (exit $ec). Full output: $LOG_FILE"
	else
		wt --title "Phase failed" --scrolltext --msgbox \
			"$title exited with status $ec.\n\nLast output:\n$tail_text\n\nFull output:\n  $LOG_FILE\n\nFix the error and re-run ./omaxian-install.sh." \
			$(fit 22 78) || true
	fi
	if (( soft )); then
		return "$ec"
	fi
	exit "$ec"
}

# --- whiptail checklist → selected tags (one per line) ------------------------
# checklist <title> <prompt> <tag> <label> <state> …
checklist() {
	local title="$1" prompt="$2" h w list_h
	shift 2
	read -r h w < <(fit 20 64)
	list_h=$(( h - 8 ))
	if (( list_h < 3 )); then list_h=3; fi
	wt --title "$title" --separate-output --checklist "$prompt" \
		"$h" "$w" "$list_h" "$@" 3>&1 1>&2 2>&3
}

# --- package mode -----------------------------------------------------------
# Sets SETUP_FLAGS array: empty | --minimal | --optional
SETUP_FLAGS=()
PKG_LABEL="Recommended (default)"

choose_package_set() {
	local choice
	choice=$(wt --title "Package set" --radiolist \
		"Which system packages should setup install?\n\nRecommended covers bar widgets most people use." \
		$(fit 15 72) 3 \
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
		$(fit 17 72)
}

# --- shared dependency confirmation -------------------------------------------
# confirm_deps <title> <tree> <filter fn> <apt heading> <footer> <dirs[]> <names[]>
# Unions packages from each selected dir's omaxian.deps.json, drops the ones
# already installed, and asks to continue. names[] is parallel to dirs[].
# <filter fn> is called with a dir and prints the jq filter for its packages.
confirm_deps() {
	local title="$1" tree="$2" filter_fn="$3" apt_heading="$4" footer="$5"
	local -n dirs_ref="$6" names_ref="$7"
	local pkgs=() manuals=() need=() deps pkg note i msg filter

	if (( ${#dirs_ref[@]} == 0 )); then
		return 0
	fi
	for i in "${!dirs_ref[@]}"; do
		deps="$REPO_DIR/$tree/${dirs_ref[$i]}/omaxian.deps.json"
		[[ -f $deps ]] || continue
		filter=$("$filter_fn" "${dirs_ref[$i]}")
		while IFS= read -r pkg; do
			[[ -n $pkg ]] && pkgs+=("$pkg")
		done < <(jq -r "$filter | .[]" "$deps")
		while IFS= read -r note; do
			[[ -n $note ]] && manuals+=("$note")
		done < <(jq -r '.manual // [] | .[]' "$deps")
	done

	if (( ${#pkgs[@]} > 0 )); then
		mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | sort -u)
	fi
	for pkg in "${pkgs[@]+"${pkgs[@]}"}"; do
		if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
			continue
		fi
		need+=("$pkg")
	done

	msg="Selected:\n"
	for i in "${!dirs_ref[@]}"; do
		msg+="  • ${names_ref[$i]:-${dirs_ref[$i]}}\n"
	done
	msg+="\n"
	if (( ${#need[@]} > 0 )); then
		msg+="$apt_heading\n"
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
	msg+="\n$footer"

	wt --title "$title" --scrolltext --yesno "$msg" $(fit 22 72)
}

# --- community plugins ------------------------------------------------------
# Sets SELECTED_PLUGIN_DIRS (basenames under community-plugins/) and the
# parallel SELECTED_PLUGIN_NAMES.
SELECTED_PLUGIN_DIRS=()
SELECTED_PLUGIN_NAMES=()

ask_install_plugins() {
	wt --title "Community plugins" --defaultno --yesno \
		"Install optional community plugins from this repo?\n\n\
They are NOT part of the default desktop. You can pick which ones next.\n\n\
Default: No." \
		$(fit 12 72)
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
	local list args=() dir id name tag label selected tok
	local -A tag_to_dir=() dir_to_label=()
	SELECTED_PLUGIN_DIRS=()
	SELECTED_PLUGIN_NAMES=()
	list=$("$PLUGIN_HELPER" --list) || true
	if [[ -z $list ]]; then
		wt --title "Community plugins" --msgbox "No community plugins found under community-plugins/." $(fit 8 60)
		return 0
	fi

	# whiptail checklist: short tag + short label (avoids TUI overflow)
	while IFS=$'\t' read -r dir id name; do
		[[ -n $dir ]] || continue
		tag=$(plugin_checklist_tag "$dir")
		# Two plugins with the same id suffix would share a tag; use the full dir.
		if [[ -n ${tag_to_dir[$tag]:-} ]]; then
			tag=$dir
		fi
		label=$(plugin_checklist_label "$dir" "$name")
		tag_to_dir[$tag]=$dir
		dir_to_label[$dir]=$label
		args+=("$tag" "$label" OFF)
	done <<< "$list"

	if (( ${#args[@]} == 0 )); then
		return 0
	fi

	selected=$(checklist "Select community plugins" \
		"Space toggles. Speaker calibrators are mutually exclusive — pick at most one." \
		"${args[@]}") || return 1

	while IFS= read -r tok; do
		[[ -n $tok ]] || continue
		SELECTED_PLUGIN_DIRS+=("${tag_to_dir[$tok]}")
	done <<< "$selected"

	# Enforce calibrator exclusivity
	local has_pulse=0 has_pipe=0
	for tok in "${SELECTED_PLUGIN_DIRS[@]+"${SELECTED_PLUGIN_DIRS[@]}"}"; do
		[[ $tok == "omaxian-speaker-pulseaudio-calibrator" ]] && has_pulse=1
		[[ $tok == "omaxian-speaker-pipewire-calibrator" ]] && has_pipe=1
	done
	if (( has_pulse && has_pipe )); then
		local pick filtered=()
		pick=$(wt --title "Speaker calibrator" --radiolist \
			"Both audio calibrators were selected. Choose one audio stack:" \
			$(fit 12 60) 2 \
			pulse "PulseAudio" ON \
			pipewire "PipeWire" OFF \
			3>&1 1>&2 2>&3) || return 1
		for tok in "${SELECTED_PLUGIN_DIRS[@]}"; do
			if [[ $tok == "omaxian-speaker-pulseaudio-calibrator" || $tok == "omaxian-speaker-pipewire-calibrator" ]]; then
				continue
			fi
			filtered+=("$tok")
		done
		if [[ $pick == "pipewire" ]]; then
			filtered+=(omaxian-speaker-pipewire-calibrator)
		else
			filtered+=(omaxian-speaker-pulseaudio-calibrator)
		fi
		SELECTED_PLUGIN_DIRS=("${filtered[@]}")
	fi

	for dir in "${SELECTED_PLUGIN_DIRS[@]+"${SELECTED_PLUGIN_DIRS[@]}"}"; do
		SELECTED_PLUGIN_NAMES+=("${dir_to_label[$dir]:-$dir}")
	done
	return 0
}

plugin_deps_filter() {
	echo '.apt // []'
}

confirm_plugin_deps() {
	confirm_deps "Plugin dependencies" community-plugins plugin_deps_filter \
		"apt packages (sudo):" "Continue?" \
		SELECTED_PLUGIN_DIRS SELECTED_PLUGIN_NAMES
}

# Returns non-zero when the plugin helper failed (desktop stays installed).
install_selected_plugins() {
	if (( ${#SELECTED_PLUGIN_DIRS[@]} == 0 )); then
		return 0
	fi
	ensure_sudo
	run_phase --soft "Community plugins" "$PLUGIN_HELPER" "${SELECTED_PLUGIN_DIRS[@]}"
}

# --- community apps ---------------------------------------------------------
# Sets SELECTED_APP_DIRS (basenames under community-apps/) and the parallel
# SELECTED_APP_NAMES.
SELECTED_APP_DIRS=()
SELECTED_APP_NAMES=()
FAILED_APPS=()
# 1 = pass --from-source to every app (user chose to compile).
APPS_FROM_SOURCE=0

ask_install_apps() {
	wt --title "Community apps" --defaultno --yesno \
		"Install optional community apps from this repo?\n\n\
Standalone ports (file manager, editor, recorder, …).\n\
They are NOT part of the default desktop. You can pick which ones next.\n\n\
Apps with a pre-built binary download in seconds; the rest compile,\n\
which may take several minutes. Default: No." \
		$(fit 15 74)
}

# True when <dir> pins a pre-built binary for this machine. install.sh makes
# the final call (Qt version, local changes, download); it falls back to a
# source build on its own.
app_has_prebuilt() {
	local manifest="$REPO_DIR/community-apps/$1/.omaxian-prebuilt" arch
	[[ -f $manifest ]] || return 1
	arch=$(awk -F= '$1 == "arch" { print $2; exit }' "$manifest")
	[[ ${arch:-x86_64} == "$(uname -m)" ]]
}

# Prints the jq filter for the packages <dir> needs in the chosen mode.
app_deps_filter() {
	if (( ! APPS_FROM_SOURCE )) && app_has_prebuilt "$1"; then
		echo '.apt // []'
	else
		echo '(.apt // []) + (.apt_build // [])'
	fi
}

# Download or compile, asked only when a selected app has a pre-built binary.
choose_app_build_mode() {
	local dir any=0 choice
	APPS_FROM_SOURCE=0
	for dir in "${SELECTED_APP_DIRS[@]}"; do
		if app_has_prebuilt "$dir"; then any=1; fi
	done
	(( any )) || return 0
	choice=$(wt --title "Community apps" --radiolist \
		"Some selected apps have a pre-built, checksum-pinned binary.\n\nHow should they be installed?" \
		$(fit 14 74) 2 \
		download "Download pre-built binaries (fast)" ON \
		source "Build everything from source" OFF \
		3>&1 1>&2 2>&3) || return 1
	if [[ $choice == "source" ]]; then
		APPS_FROM_SOURCE=1
	fi
	return 0
}

# Short checklist tag — long directory names overflow a ~78-col whiptail box.
app_checklist_tag() {
	local dir="$1"
	case "$dir" in
		omarchy-meeting-recorder) echo "meeting" ;;
		*) echo "$dir" ;;
	esac
}

choose_apps() {
	local list args=() dir name tag selected tok
	local -A tag_to_dir=() dir_to_name=()
	SELECTED_APP_DIRS=()
	SELECTED_APP_NAMES=()
	list=$("$APP_HELPER" --list) || true
	if [[ -z $list ]]; then
		wt --title "Community apps" --msgbox "No community apps found under community-apps/." $(fit 8 60)
		return 0
	fi

	while IFS=$'\t' read -r dir name; do
		[[ -n $dir ]] || continue
		tag=$(app_checklist_tag "$dir")
		if [[ -n ${tag_to_dir[$tag]:-} ]]; then
			tag=$dir
		fi
		tag_to_dir[$tag]=$dir
		dir_to_name[$dir]=$name
		args+=("$tag" "$name" OFF)
	done <<< "$list"

	if (( ${#args[@]} == 0 )); then
		return 0
	fi

	selected=$(checklist "Select community apps" \
		"Space toggles. Each app installs via its own install.sh." \
		"${args[@]}") || return 1

	while IFS= read -r tok; do
		[[ -n $tok ]] || continue
		dir=${tag_to_dir[$tok]}
		SELECTED_APP_DIRS+=("$dir")
		SELECTED_APP_NAMES+=("${dir_to_name[$dir]:-$dir}")
	done <<< "$selected"

	return 0
}

confirm_app_deps() {
	local footer i list downloads=() builds=()
	for i in "${!SELECTED_APP_DIRS[@]}"; do
		if (( ! APPS_FROM_SOURCE )) && app_has_prebuilt "${SELECTED_APP_DIRS[$i]}"; then
			downloads+=("${SELECTED_APP_NAMES[$i]}")
		else
			builds+=("${SELECTED_APP_NAMES[$i]}")
		fi
	done
	footer=""
	if (( ${#downloads[@]} > 0 )); then
		list=$(printf '%s, ' "${downloads[@]}")
		footer+="Download (sha256-checked): ${list%, }\n"
	fi
	if (( ${#builds[@]} > 0 )); then
		list=$(printf '%s, ' "${builds[@]}")
		footer+="Build from source: ${list%, }\n"
	fi
	if (( ${#downloads[@]} > 0 )); then
		footer+="A download that cannot be used falls back to a build,\nwhich also installs that app's build packages.\n"
	fi
	footer+="Everything installs under ~/.local.\nContinue?"
	confirm_deps "App dependencies" community-apps app_deps_filter \
		"apt packages (sudo):" "$footer" \
		SELECTED_APP_DIRS SELECTED_APP_NAMES
}

# Fills FAILED_APPS with the display names of apps whose install.sh failed.
install_selected_apps() {
	local report dir line
	local -A dir_to_name=()
	FAILED_APPS=()
	if (( ${#SELECTED_APP_DIRS[@]} == 0 )); then
		return 0
	fi
	for line in "${!SELECTED_APP_DIRS[@]}"; do
		dir_to_name[${SELECTED_APP_DIRS[$line]}]=${SELECTED_APP_NAMES[$line]}
	done
	ensure_sudo
	report=$(mktemp "${TMPDIR:-/tmp}/omaxian-apps.XXXXXX")
	local mode=()
	if (( APPS_FROM_SOURCE )); then mode=(--from-source); fi
	run_phase --soft "Community apps" "$APP_HELPER" --report "$report" \
		"${mode[@]+"${mode[@]}"}" "${SELECTED_APP_DIRS[@]}" || true
	while IFS=$'\t' read -r line dir; do
		if [[ $line == "failed" ]]; then
			FAILED_APPS+=("${dir_to_name[$dir]:-$dir}")
		fi
	done <"$report"
	rm -f -- "$report"
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
	local id version_id
	id=$(os_release_field ID)
	version_id=$(os_release_field VERSION_ID)
	case "$id" in
		devuan) echo "devuan" ;;
		debian)
			# 13 = trixie; testing pin is often needed there.
			if [[ ${version_id%%.*} == "13" ]]; then
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
				$(fit 10 64) || true
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

	wt --title "Quickshell required" --scrolltext --msgbox "$(echo -e "$text")" $(fit 22 72) || true
}

# --- main -------------------------------------------------------------------
run_desktop() {
	local spinner=0
	if tui_phases; then spinner=1; fi
	ensure_sudo
	# setup.sh re-execs as root; sudo's env reset drops our variables, so pass
	# them explicitly. The bar splits the desktop by rough phase duration.
	run_phase --pct 0 70 "1/3  System packages (setup.sh)" \
		sudo -n env OMAXIAN_NESTED=1 OMAXIAN_TUI_SPINNER="$spinner" \
		"$SETUP" "${SETUP_FLAGS[@]+"${SETUP_FLAGS[@]}"}"

	run_phase --pct 70 90 "2/3  Themes and commands (install.sh)" "$INSTALL"

	run_phase --pct 90 100 "3/3  Home configs (deploy.sh)" "$DEPLOY"
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
	if [[ -n $extra ]]; then
		text+="\n$extra\n"
	fi
	text+="\nInstall log: $LOG_FILE"
	if (( NONINTERACTIVE )); then
		echo
		omaxian_done "install finished"
		echo -e "$text"
	else
		wt --title "Done" --scrolltext --msgbox "$(echo -e "$text")" $(fit 22 72) || true
	fi
}

# Join extras[] with newlines for final_checklist.
join_extras() {
	if (( $# > 0 )); then
		printf '%s\n' "$@"
	fi
}

main_interactive() {
	omaxian_banner
	omaxian_msg "installer ${OMAXIAN_VERSION}"
	preflight
	# Asks before using sudo; only installs what is missing.
	ensure_preflight_tools whiptail dialog git

	local welcome warn
	welcome="Omaxian ${OMAXIAN_VERSION}\n\
Omarchy for Devuan/Debian + X11 + i3.\n\n\
This installer will:\n\
  • install system packages (sudo)\n\
  • seed themes and omarchy-* commands\n\
  • deploy i3 / Quickshell configs\n\
  • verify Quickshell (required for the bar)\n\
  • optionally install community plugins\n\
  • optionally install community apps\n\n\
Repo: $REPO_DIR\n"
	if (( ${#PREFLIGHT_WARNINGS[@]} > 0 )); then
		welcome+="\nWarnings:\n"
		for warn in "${PREFLIGHT_WARNINGS[@]}"; do
			welcome+="  ! $warn\n"
		done
	fi
	welcome+="\nContinue?"
	wt --title "Welcome" --scrolltext --yesno "$welcome" $(fit 22 72) || { omaxian_msg "cancelled"; exit 1; }

	choose_package_set || { omaxian_msg "cancelled"; exit 1; }
	confirm_desktop || { omaxian_msg "cancelled"; exit 1; }

	run_desktop
	check_quickshell

	local extras=()
	if ask_install_plugins; then
		choose_plugins || { omaxian_msg "plugin selection cancelled — desktop is installed"; final_checklist; exit 0; }
		if (( ${#SELECTED_PLUGIN_DIRS[@]} > 0 )); then
			confirm_plugin_deps || { omaxian_msg "plugin deps declined — desktop is installed"; final_checklist; exit 0; }
			if install_selected_plugins; then
				extras+=("Community plugins → ~/.config/omarchy/plugins/.\nEnable under Settings → Plugins after login if needed.")
			else
				extras+=("!! Community plugins failed to install. See the install log.")
			fi
		fi
	fi

	if ask_install_apps; then
		choose_apps || { omaxian_msg "app selection cancelled — desktop is installed"; final_checklist "$(join_extras "${extras[@]+"${extras[@]}"}")"; exit 0; }
		if (( ${#SELECTED_APP_DIRS[@]} > 0 )); then
			choose_app_build_mode || { omaxian_msg "app install cancelled — desktop is installed"; final_checklist "$(join_extras "${extras[@]+"${extras[@]}"}")"; exit 0; }
			confirm_app_deps || { omaxian_msg "app deps declined — desktop is installed"; final_checklist "$(join_extras "${extras[@]+"${extras[@]}"}")"; exit 0; }
			install_selected_apps
			if (( ${#FAILED_APPS[@]} < ${#SELECTED_APP_DIRS[@]} )); then
				extras+=("Community apps → ~/.local (bin + .desktop).\nSee community-apps/README.md for per-app notes.")
			fi
			if (( ${#FAILED_APPS[@]} > 0 )); then
				local failed
				failed=$(printf '%s, ' "${FAILED_APPS[@]}")
				extras+=("!! Failed apps: ${failed%, }. See the install log.")
			fi
		fi
	fi

	final_checklist "$(join_extras "${extras[@]+"${extras[@]}"}")"
}

main_noninteractive() {
	local warn
	SETUP_FLAGS=()
	PKG_LABEL="Recommended (default)"
	omaxian_banner
	omaxian_msg "installer ${OMAXIAN_VERSION}  (noninteractive)"
	omaxian_info "recommended packages + install + deploy (no community plugins/apps)"
	preflight
	for warn in "${PREFLIGHT_WARNINGS[@]+"${PREFLIGHT_WARNINGS[@]}"}"; do
		omaxian_err "warning: $warn"
	done
	# setup.sh clones upstream with git before it installs its own packages.
	ensure_preflight_tools git
	run_desktop
	check_quickshell
	final_checklist "Community plugins/apps skipped (--yes). Re-run ./omaxian-install.sh or see community-plugins/README.md and community-apps/README.md."
}

if (( NONINTERACTIVE )); then
	main_noninteractive
else
	main_interactive
fi
