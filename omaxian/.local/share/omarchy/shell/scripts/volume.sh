#!/usr/bin/env bash
# Volume helpers: get | set <pct> | mute-toggle | up | down
set -euo pipefail

cmd="${1:-get}"
case "$cmd" in
	get)
		vol="$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | awk '{print $5; exit}' | tr -d '%')"
		echo "${vol:-0}"
		;;
	set)
		pactl set-sink-volume @DEFAULT_SINK@ "${2:-50}%"
		;;
	mute-toggle)
		pactl set-sink-mute @DEFAULT_SINK@ toggle
		;;
	up)
		pactl set-sink-volume @DEFAULT_SINK@ +5%
		;;
	down)
		pactl set-sink-volume @DEFAULT_SINK@ -5%
		;;
	*)
		echo "usage: volume.sh get|set <pct>|mute-toggle|up|down" >&2
		exit 1
		;;
esac
