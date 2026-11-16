# Shared install-script UI helpers (banner + quiet step logs).
# Sourced by omaxian-install.sh, scripts/install.sh, scripts/deploy.sh.
# shellcheck shell=bash

# True when stdout is a TTY and colour is not disabled.
omaxian_ui_color() {
	[[ -t 1 ]] || return 1
	[[ -z ${NO_COLOR:-} ]] || return 1
	[[ ${TERM:-dumb} != dumb ]] || return 1
	return 0
}

# Wordmark: block figlet-style OMAXIAN with magenta X (matches banner.png).
# Skipped when OMAXIAN_NESTED=1 (child of omaxian-install.sh programbox).
omaxian_banner() {
	if [[ ${OMAXIAN_NESTED:-0} == 1 ]]; then
		return 0
	fi
	local c_cyan='' c_mag='' c_rst=''
	if omaxian_ui_color; then
		c_cyan=$'\033[38;2;94;234;212m'
		c_mag=$'\033[38;2;236;72;153m'
		c_rst=$'\033[0m'
	fi
	# shellcheck disable=SC2059
	printf '%s\n' \
		"${c_cyan}  _|_|    _|      _|    _|_|  ${c_mag}_|      _|${c_cyan}  _|_|_|    _|_|    _|      _|${c_rst}" \
		"${c_cyan}_|    _|  _|_|  _|_|  _|    _|${c_mag}  _|  _|  ${c_cyan}  _|    _|    _|  _|_|    _|${c_rst}" \
		"${c_cyan}_|    _|  _|  _|  _|  _|_|_|_|${c_mag}    _|    ${c_cyan}  _|    _|_|_|_|  _|  _|  _|${c_rst}" \
		"${c_cyan}_|    _|  _|      _|  _|    _|${c_mag}  _|  _|  ${c_cyan}  _|    _|    _|  _|    _|_|${c_rst}" \
		"${c_cyan}  _|_|    _|      _|  _|    _|${c_mag}_|      _|${c_cyan}  _|_|_|  _|    _|  _|      _|${c_rst}"
	echo
}

# One-line phase title:  -- 1/4  label
omaxian_phase() {
	echo
	echo "-- $1"
}

# Informational line (quiet).
omaxian_info() {
	echo "   $*"
}

# Primary status line.
omaxian_msg() {
	echo ":: $*"
}

# Error / warning to stderr.
omaxian_err() {
	echo "!! $*" >&2
}

# Closing rule (single line, not a wall of equals).
omaxian_done() {
	echo
	echo "== $* =="
}

# Label the step that starts now (e.g. before a quiet loop or a slow command
# whose output is hidden). omaxian-install.sh shows the latest step next to
# its spinner; the "   label ..." shape is what it looks for.
omaxian_step() {
	echo "   $* ..."
}

# Run a long quiet command with a loader so the TUI/TTY does not look stuck.
# Usage: omaxian_spin "label" command [args…]
# - TTY: in-place |/-\ spinner on one line
# - Under omaxian-install.sh's TUI (OMAXIAN_TUI_SPINNER=1): the installer
#   draws the spinner; print only the start and end lines
# - Otherwise piped (--yes, logs): a heartbeat line with elapsed time every ~10s
# Command stdout/stderr go to a temp log; dumped on failure.
omaxian_spin() {
	local label="$1"
	shift
	(( $# > 0 )) || {
		omaxian_err "omaxian_spin: missing command"
		return 2
	}

	local log pid ec=0 frames i=0 next_beat=0 now
	log=$(mktemp "${TMPDIR:-/tmp}/omaxian-spin.XXXXXX") || return 1

	"$@" >"$log" 2>&1 &
	pid=$!

	# shellcheck disable=SC2064
	trap "kill $pid 2>/dev/null || true; rm -f -- '$log'" INT TERM

	if [[ -t 1 ]]; then
		frames='|/-\'
		printf '   %s  ' "$label"
		while kill -0 "$pid" 2>/dev/null; do
			printf '\b%s' "${frames:i++%${#frames}:1}"
			sleep 0.12
		done
		wait "$pid" || ec=$?
		if (( ec == 0 )); then
			printf '\bdone\n'
		else
			printf '\bfailed\n'
		fi
	else
		# Not a TTY: \r redraws do nothing useful, so print whole lines.
		local start=$SECONDS
		omaxian_step "$label"
		next_beat=$((SECONDS + 10))
		while kill -0 "$pid" 2>/dev/null; do
			sleep 0.5
			now=$SECONDS
			if [[ ${OMAXIAN_TUI_SPINNER:-0} != "1" ]] && (( now >= next_beat )); then
				printf '   ... still working (%s, %d:%02d)\n' "$label" $(( (now - start) / 60 )) $(( (now - start) % 60 ))
				next_beat=$((now + 10))
			fi
		done
		wait "$pid" || ec=$?
		if (( ec == 0 )); then
			echo "   $label - done"
		else
			echo "   $label - failed"
		fi
	fi

	trap - INT TERM

	if (( ec != 0 )); then
		omaxian_err "$label failed (exit $ec)"
		# Cap dump so a huge apt log does not flood the programbox.
		tail -n 40 "$log" >&2 || true
		rm -f -- "$log"
		return "$ec"
	fi
	rm -f -- "$log"
	return 0
}
