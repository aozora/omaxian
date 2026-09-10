#!/usr/bin/env bash
# Current XKB layout (+ Caps Lock hint). `next` cycles the group. `watch`
# prints a line whenever the group (or Caps Lock) changes — used by the bar
# widget instead of a blind poll (upstream Hyprland had activelayout IPC).
#
# Cycle order: xkb-switch -n, else XkbLockGroup to the next group (same effect
# as grp:*_toggle), else rotate the setxkbmap layout list.
set -euo pipefail

# Shared Python: group index, lock-next, and optional XkbStateNotify watch.
# XkbQueryExtension is required before reliable XkbGetState on some servers.
xkb_py() {
	local mode="${1:-group}"
	python3 - "$mode" <<'PY'
import ctypes
import ctypes.util
import sys

mode = sys.argv[1] if len(sys.argv) > 1 else "group"

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

class XEvent(ctypes.Structure):
	_fields_ = [("pad", ctypes.c_long * 24)]

XOpenDisplay = x11.XOpenDisplay
XOpenDisplay.argtypes = [ctypes.c_char_p]
XOpenDisplay.restype = ctypes.c_void_p
XCloseDisplay = x11.XCloseDisplay
XCloseDisplay.argtypes = [ctypes.c_void_p]
XFlush = x11.XFlush
XFlush.argtypes = [ctypes.c_void_p]
XSync = x11.XSync
XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
XNextEvent = x11.XNextEvent
XNextEvent.argtypes = [ctypes.c_void_p, ctypes.POINTER(XEvent)]
XNextEvent.restype = ctypes.c_int

XkbQueryExtension = x11.XkbQueryExtension
XkbQueryExtension.argtypes = [
	ctypes.c_void_p,
	ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
	ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
	ctypes.POINTER(ctypes.c_int),
]
XkbQueryExtension.restype = ctypes.c_int

XkbGetState = x11.XkbGetState
XkbGetState.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.POINTER(XkbStateRec)]
XkbGetState.restype = ctypes.c_int

XkbLockGroup = x11.XkbLockGroup
XkbLockGroup.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_uint]
XkbLockGroup.restype = ctypes.c_int

XkbSelectEvents = x11.XkbSelectEvents
XkbSelectEvents.argtypes = [
	ctypes.c_void_p, ctypes.c_uint, ctypes.c_ulong, ctypes.c_ulong,
]
XkbSelectEvents.restype = ctypes.c_int

XkbUseCoreKbd = 0x0100
# XkbStateNotifyMask in XKBstr.h
XkbStateNotifyMask = 1 << 2

def open_display():
	dpy = XOpenDisplay(None)
	if not dpy:
		return None
	opcode = ctypes.c_int()
	event = ctypes.c_int()
	error = ctypes.c_int()
	major = ctypes.c_int(1)
	minor = ctypes.c_int(0)
	if not XkbQueryExtension(
		dpy, ctypes.byref(opcode), ctypes.byref(event), ctypes.byref(error),
		ctypes.byref(major), ctypes.byref(minor),
	):
		XCloseDisplay(dpy)
		return None
	return dpy

def read_state(dpy):
	state = XkbStateRec()
	XkbGetState(dpy, XkbUseCoreKbd, ctypes.byref(state))
	# Effective group is what typing uses after Alt+Shift / ISO_Next_Group.
	group = int(state.group)
	# Caps Lock is the Lock modifier (1<<1) in locked_mods.
	caps = 1 if (int(state.locked_mods) & 0x2) else 0
	return group, caps

def read_group(dpy):
	return read_state(dpy)[0]

if mode == "group":
	dpy = open_display()
	if not dpy:
		print(0)
		sys.exit(0)
	print(read_group(dpy))
	XCloseDisplay(dpy)
	sys.exit(0)

if mode == "next":
	# argv: next <group-count>
	count = int(sys.argv[2]) if len(sys.argv) > 2 else 2
	if count < 1:
		count = 1
	dpy = open_display()
	if not dpy:
		sys.exit(1)
	cur = read_group(dpy)
	XkbLockGroup(dpy, XkbUseCoreKbd, (cur + 1) % count)
	XSync(dpy, False)
	XCloseDisplay(dpy)
	sys.exit(0)

if mode == "watch-signal":
	# Print "group\\tcaps" on start and on every XkbStateNotify.
	try:
		sys.stdout.reconfigure(line_buffering=True)
	except Exception:
		pass
	dpy = open_display()
	if not dpy:
		sys.exit(1)
	XkbSelectEvents(dpy, XkbUseCoreKbd, XkbStateNotifyMask, XkbStateNotifyMask)
	last = None
	while True:
		g, c = read_state(dpy)
		cur = (g, c)
		if cur != last:
			last = cur
			print(f"{g}\t{c}", flush=True)
		ev = XEvent()
		XNextEvent(dpy, ctypes.byref(ev))

print("unknown mode", mode, file=sys.stderr)
sys.exit(2)
PY
}

xkb_group_index() {
	xkb_py group
}

layout_list_from_rules() {
	local layouts
	layouts="$(xprop -root _XKB_RULES_NAMES 2>/dev/null \
		| awk -F'"' '{print $6; exit}')"
	if [[ -z $layouts || $layouts == "STRING" ]]; then
		layouts="$(setxkbmap -query 2>/dev/null | awk '/layout:/{print $2; exit}')"
	fi
	printf '%s' "${layouts:-}"
}

# Live symbols can disagree with _XKB_RULES_NAMES (session hooks / greeter /
# a later setxkbmap -layout that only refreshed the atom). Parse the compiled
# map so Alt+Shift group changes still label RU/US/… correctly.
layout_list_from_symbols() {
	local sym
	sym="$(xkbcomp -xkb "${DISPLAY:-:0}" - 2>/dev/null \
		| awk '/xkb_symbols / { gsub(/"/, "", $2); print $2; exit }')"
	[[ -n $sym ]] || return 0
	python3 - "$sym" <<'PY'
import re, sys
sym = sys.argv[1]
parts = []
for bit in sym.split("+"):
	if bit == "pc" or bit.startswith("inet(") or bit.startswith("group("):
		continue
	bit = re.sub(r":\d+$", "", bit)
	name = re.sub(r"\(.*\)$", "", bit)
	if name and re.fullmatch(r"[a-z0-9_]+", name):
		parts.append(name)
print(",".join(parts))
PY
}

csv_len() {
	local s="${1-}"
	[[ -n $s ]] || { printf '0'; return; }
	local -a a=()
	IFS=',' read -r -a a <<<"$s"
	printf '%s' "${#a[@]}"
}

layout_list() {
	local rules eff
	rules="$(layout_list_from_rules)"
	eff="$(layout_list_from_symbols || true)"
	# Prefer the longer list — rules often lag with a single system layout
	# (e.g. /etc/default/keyboard XKBLAYOUT=it) while the map still has it,ru.
	if [[ -n $eff ]] && (( $(csv_len "$eff") >= $(csv_len "$rules") )); then
		printf '%s' "$eff"
	elif [[ -n $rules ]]; then
		printf '%s' "$rules"
	elif [[ -n $eff ]]; then
		printf '%s' "$eff"
	else
		printf '??'
	fi
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

	# Lock the next XKB group — same effect Alt+Shift has with grp:*_toggle,
	# without relying on xdotool synthetic keys (often swallowed by grabs).
	local layouts
	local -a layout_arr=()
	layouts="$(layout_list)"
	IFS=',' read -r -a layout_arr <<<"$layouts"
	if ((${#layout_arr[@]} > 1)); then
		xkb_py next "${#layout_arr[@]}" && return
	fi

	local layout variant options
	local -a L=() V=() new_l=() new_v=()
	layout="$(query_field layout)"
	[[ -n $layout && $layout != "??" ]] || return 0
	IFS=',' read -r -a L <<<"$layout"
	((${#L[@]} > 1)) || return 0

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
	if [[ -n $variant ]]; then
		cmd+=(-variant "$(join_csv "${new_v[@]}")")
	fi
	if [[ -n $options ]]; then
		cmd+=(-option "$options")
	fi
	"${cmd[@]}"
}

format_status_with() {
	local layouts="$1" group="$2" caps_flag="${3:-0}"
	local idx layout caps
	local -a layout_arr=()
	IFS=',' read -r -a layout_arr <<<"$layouts"
	idx="${group:-0}"
	if ((idx < 0 || idx >= ${#layout_arr[@]})); then
		idx=0
	fi
	layout="$(echo "${layout_arr[$idx]}" | tr '[:lower:]' '[:upper:]')"
	layout="${layout:-??}"

	caps=""
	if [[ $caps_flag == "1" ]]; then
		caps=" 󰘲"
	elif [[ $caps_flag == "auto" ]]; then
		if command -v xset >/dev/null 2>&1; then
			if xset q 2>/dev/null | grep -q "Caps Lock:   on"; then
				caps=" 󰘲"
			fi
		fi
	fi
	# nf-mdi-keyboard U+F80B — keep as a literal so the bar font can render it.
	printf ' %s%s\n' "$layout" "$caps"
}

format_status() {
	format_status_with "$(layout_list)" "$1" "${2:-0}"
}

print_status() {
	local group
	group="$(xkb_group_index)"
	format_status "$group" auto
}

watch_status() {
	# Resolve the layout list once; refresh if the group index walks past it
	# (rules atom caught up, or a setxkbmap ran). Avoid xkbcomp on every
	# XkbStateNotify — that fires for ordinary modifier noise too.
	local group caps layouts
	local -a layout_arr=()
	layouts="$(layout_list)"
	while IFS=$'\t' read -r group caps; do
		[[ $group =~ ^[0-9]+$ ]] || continue
		IFS=',' read -r -a layout_arr <<<"$layouts"
		if (( group >= ${#layout_arr[@]} )); then
			layouts="$(layout_list)"
		fi
		format_status_with "$layouts" "$group" "${caps:-0}"
	done < <(xkb_py watch-signal)
}

case "${1:-}" in
	next | cycle)
		cycle_next
		print_status
		;;
	watch)
		watch_status
		;;
	"" | status)
		print_status
		;;
	*)
		echo "usage: keyboard.sh [status|next|watch]" >&2
		exit 1
		;;
esac
