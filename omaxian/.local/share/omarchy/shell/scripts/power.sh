#!/usr/bin/env bash
# Power actions (lock / logout / suspend / hibernate / reboot / poweroff).
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

I3_SCRIPTS="${HOME}/.config/i3/scripts"
action="${1:-}"

close_menus

case "$action" in
	lock)
		if [[ -x "$I3_SCRIPTS/i3_lock" ]]; then
			"$I3_SCRIPTS/i3_lock"
		elif command -v i3lock-fancy >/dev/null 2>&1; then
			i3lock-fancy
		elif command -v i3lock >/dev/null 2>&1; then
			i3lock -c 24273A
		fi
		;;
	logout)
		if command -v i3-msg >/dev/null 2>&1 && pgrep -x i3 >/dev/null 2>&1; then
			# unset I3SOCK — the shell tree may carry a stale path (see
			# plugins/bar/widgets/Workspaces.qml); fall back to the X property.
			unset I3SOCK
			i3-msg exit
		elif command -v loginctl >/dev/null 2>&1; then
			loginctl terminate-session "${XDG_SESSION_ID:-}"
		fi
		;;
	suspend)
		command -v loginctl >/dev/null 2>&1 && loginctl suspend
		;;
	hibernate)
		command -v loginctl >/dev/null 2>&1 && loginctl hibernate
		;;
	reboot)
		command -v loginctl >/dev/null 2>&1 && loginctl reboot
		;;
	shutdown|poweroff)
		command -v loginctl >/dev/null 2>&1 && loginctl poweroff
		;;
	*)
		echo "usage: power.sh lock|logout|suspend|hibernate|reboot|shutdown" >&2
		exit 1
		;;
esac
