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
		elif command -v i3lock-omaxian >/dev/null 2>&1; then
			i3lock-omaxian
		elif command -v i3lock-fancy >/dev/null 2>&1; then
			i3lock-fancy
		elif command -v i3lock >/dev/null 2>&1; then
			i3lock -c 24273A
		fi
		;;
	logout)
		omarchy-host logout
		;;
	suspend)
		omarchy-host suspend
		;;
	hibernate)
		omarchy-host hibernate
		;;
	reboot)
		omarchy-host reboot
		;;
	shutdown|poweroff)
		omarchy-host poweroff
		;;
	*)
		echo "usage: power.sh lock|logout|suspend|hibernate|reboot|shutdown" >&2
		exit 1
		;;
esac
