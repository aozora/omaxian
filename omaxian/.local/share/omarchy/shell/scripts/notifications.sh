#!/usr/bin/env bash
# Pop last dunst notification.
set -euo pipefail

if [[ -x "${HOME}/.config/i3/scripts/i3_notifications" ]]; then
	exec "${HOME}/.config/i3/scripts/i3_notifications"
fi
dunstctl history-pop 2>/dev/null || true
