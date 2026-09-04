#!/usr/bin/env bash
# Current XKB layout (+ Caps Lock hint). `next` cycles the group.
#
# Cycle order: xkb-switch -n, then ISO_Next_Group (the same keysym
# grp:*_toggle options use), then rotate the setxkbmap layout list.
set -euo pipefail

xkb_group_index() {
	python3 - <<'PY'
import ctypes
import ctypes.util
import sys

x11 = ctypes.CDLL(ctypes.util.find_library("X11"))

class XkbStateRec(ctypes.Structure):
	_fields_ = [
		("group", ctypes.c_ubyte),
		("locked_group", ctypes.c_ubyte),
		("base_group", ctypes.c_ushort),
		("latched_group", ctypes.c_ushort),
		("mods", ctypes.c_ubyte),
		("base_mods", ctypes.c_ubyte),
		("latched_mods", ctypes.c_ubyte),
		("locked_mods", ctypes.c_ubyte),
		("compat_state", ctypes.c_ubyte),
		("grab_mods", ctypes.c_ubyte),
		("compat_grab_mods", ctypes.c_ubyte),
		("lookup_mods", ctypes.c_ubyte),
		("compat_lookup_mods", ctypes.c_ubyte),
		("ptr_buttons", ctypes.c_ushort),
	]

XOpenDisplay = x11.XOpenDisplay
XOpenDisplay.argtypes = [ctypes.c_char_p]
XOpenDisplay.restype = ctypes.c_void_p
XkbGetState = x11.XkbGetState
XkbGetState.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.POINTER(XkbStateRec)]
XkbGetState.restype = ctypes.c_int
XCloseDisplay = x11.XCloseDisplay
XCloseDisplay.argtypes = [ctypes.c_void_p]

dpy = XOpenDisplay(None)
if not dpy:
	print(0)
	sys.exit(0)
state = XkbStateRec()
# XkbUseCoreKbd = 0x0100
XkbGetState(dpy, 0x0100, ctypes.byref(state))
XCloseDisplay(dpy)
print(int(state.group))
PY
}

layout_list() {
	local layouts
	layouts="$(xprop -root _XKB_RULES_NAMES 2>/dev/null \
		| awk -F'"' '{print $6; exit}')"
	if [[ -z "$layouts" || "$layouts" == "STRING" ]]; then
		layouts="$(setxkbmap -query 2>/dev/null | awk '/layout:/{print $2; exit}')"
	fi
	printf '%s' "${layouts:-??}"
}

query_field() {
	setxkbmap -query 2>/dev/null | awk -v k="$1" '$1 == k":" { print $2; exit }'
}

join_csv() {
	local IFS=,
	printf '%s' "$*"
}

cycle_next() {
	if command -v xkb-switch >/dev/null 2>&1; then
		xkb-switch -n
		return
	fi

	# Same action Alt+Shift performs when grp:alt_shift_toggle is set:
	# layouts are already loaded as XKB groups; ISO_Next_Group advances.
	if command -v xdotool >/dev/null 2>&1; then
		xdotool key --clearmodifiers ISO_Next_Group
		return
	fi

	local layout variant options
	local -a L=() V=() new_l=() new_v=()
	layout="$(query_field layout)"
	[[ -n "$layout" && "$layout" != "??" ]] || return 0
	IFS=',' read -r -a L <<<"$layout"
	(( ${#L[@]} > 1 )) || return 0

	variant="$(query_field variant)"
	options="$(query_field options)"
	IFS=',' read -r -a V <<<"$variant"

	local i
	for ((i = 1; i < ${#L[@]}; i++)); do
		new_l+=("${L[i]}")
		new_v+=("${V[i]:-}")
	done
	new_l+=("${L[0]}")
	new_v+=("${V[0]:-}")

	local cmd=(setxkbmap -layout "$(join_csv "${new_l[@]}")")
	if [[ -n "$variant" ]]; then
		cmd+=(-variant "$(join_csv "${new_v[@]}")")
	fi
	if [[ -n "$options" ]]; then
		cmd+=(-option "$options")
	fi
	"${cmd[@]}"
}

print_status() {
	local layouts group idx layout caps
	local -a layout_arr=()
	layouts="$(layout_list)"
	group="$(xkb_group_index)"
	IFS=',' read -r -a layout_arr <<<"$layouts"
	idx="${group:-0}"
	if (( idx < 0 || idx >= ${#layout_arr[@]} )); then
		idx=0
	fi
	layout="$(echo "${layout_arr[$idx]}" | tr '[:lower:]' '[:upper:]')"
	layout="${layout:-??}"

	caps=""
	if command -v xset >/dev/null 2>&1; then
		if xset q 2>/dev/null | grep -q "Caps Lock:   on"; then
			caps=" 󰘲"
		fi
	fi
	echo " ${layout}${caps}"
}

case "${1:-}" in
	next | cycle)
		cycle_next
		print_status
		;;
	"" | status)
		print_status
		;;
	*)
		echo "usage: keyboard.sh [status|next]" >&2
		exit 1
		;;
esac
