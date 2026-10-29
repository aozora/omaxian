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
