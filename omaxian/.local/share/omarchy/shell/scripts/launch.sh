#!/usr/bin/env bash
# Start Quickshell. With QS_WIDGETS_ONLY=1 (the i3_bar default) this is a
# popup host only — polybar is the visible bar and must be left running.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

eww kill 2>/dev/null || true
if [[ "${QS_WIDGETS_ONLY:-}" != "1" ]]; then
	# Full-bar mode: drop polybar so it cannot sit under/over the QS bar.
	killall -q polybar 2>/dev/null || true
fi
# Match on "-p <path>" alone, not "quickshell -p <path>": the actual
# command line is "quickshell -d -p <path>" (-d comes first), so requiring
# "quickshell -p" adjacent never matched and left the old instance running
# — confirmed live, a relaunch produced two running instances instead of
# replacing the old one.
pkill -f -- "-p ${HERE}\$" 2>/dev/null || true
sleep 0.2

quickshell -d -p "$HERE"

echo "quickshell ready (config: $HERE${QS_WIDGETS_ONLY:+, widgets-only})"
echo "  popups: qs -p '$HERE' ipc call <launcher|runner|windows|powermenu|help|calendar|weather|timer|wallpapers> toggle"
