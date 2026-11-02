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

# Run a long quiet command with a loader so the TUI/TTY does not look stuck.
# Usage: omaxian_spin "label" command [args…]
# - TTY: in-place |/-\ spinner on one line
# - Piped (dialog --programbox): heartbeat lines every ~2s
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
		# programbox is line-oriented; \r redraws do nothing useful there.
		echo "   $label ..."
		next_beat=$((SECONDS + 2))
		while kill -0 "$pid" 2>/dev/null; do
			sleep 0.5
			now=$SECONDS
			if (( now >= next_beat )); then
				echo "   ... still working ($label)"
				next_beat=$((now + 2))
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
