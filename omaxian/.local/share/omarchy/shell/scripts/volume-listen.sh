#!/usr/bin/env bash
# Print default sink volume % and mute state as JSON; refresh on PulseAudio events.
set -euo pipefail

emit() {
	local vol mute
	vol="$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | awk '{print $5; exit}' | tr -d '%')"
	mute="$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}')"
	vol="${vol:-0}"
	[[ "$mute" == "yes" ]] && mute=true || mute=false
	printf '{"volume":%s,"muted":%s}\n' "$vol" "$mute"
}

emit
pactl subscribe 2>/dev/null | while read -r line; do
	case "$line" in
		*sink*) emit ;;
	esac
done
