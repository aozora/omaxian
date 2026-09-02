#!/usr/bin/env bash
# Lightweight countdown timer (file-backed under /tmp/eww-timer).
# On expiry: notification + paplay of an alarm sound.
set -euo pipefail

TIMER_DIR=/tmp/eww-timer
ENDED_DISPLAY_SECS=12
ALARM_SOUND="${HOME}/.local/share/omarchy/shell/scripts/alarm-clock.ogg"

now() { date --utc +%s; }

timer_notify_end() {
	local icon args
	icon="$("${HOME}/.config/i3/scripts/dunst_icon" timer.png 2>/dev/null || true)"
	args=(dunstify -u normal -h string:x-dunst-stack-tag:eww-timer)
	[[ -n "$icon" ]] && args+=(-i "$icon")
	"${args[@]}" "Timer" "timer end!" 2>/dev/null \
		|| notify-send "Timer" "timer end!" 2>/dev/null \
		|| true

	if [[ -f "$ALARM_SOUND" ]] && command -v paplay >/dev/null 2>&1; then
		paplay "$ALARM_SOUND" &>/dev/null &
	fi
}

cmd="${1:-status}"

case "$cmd" in
	status)
		if [[ -f "$TIMER_DIR/ended_at" ]]; then
			elapsed=$(( $(now) - $(cat "$TIMER_DIR/ended_at") ))
			if (( elapsed < ENDED_DISPLAY_SECS )); then
				echo "󰥔 end!"
			else
				rm -rf "$TIMER_DIR"
				echo "󰥔"
			fi
		elif [[ -f "$TIMER_DIR/paused" ]]; then
			left="$(cat "$TIMER_DIR/paused")"
			printf '󰥕 %02d:%02d\n' $((left / 60)) $((left % 60))
		elif [[ -f "$TIMER_DIR/expiry" ]]; then
			left=$(( $(cat "$TIMER_DIR/expiry") - $(now) ))
			if (( left <= 0 )); then
				# Fire once, then show "end!" briefly.
				mkdir -p "$TIMER_DIR"
				if [[ ! -f "$TIMER_DIR/fired" ]]; then
					touch "$TIMER_DIR/fired"
					timer_notify_end
				fi
				echo "$(now)" >"$TIMER_DIR/ended_at"
				rm -f "$TIMER_DIR/expiry" "$TIMER_DIR/paused"
				echo "󰥔 end!"
			else
				printf '󰥔 %02d:%02d\n' $((left / 60)) $((left % 60))
			fi
		else
			echo "󰥔"
		fi
		;;
	start)
		mins="${2:-5}"
		rm -rf "$TIMER_DIR"
		mkdir -p "$TIMER_DIR"
		echo $(( $(now) + mins * 60 )) >"$TIMER_DIR/expiry"
		echo "started ${mins}m"
		;;
	pause)
		if [[ -f "$TIMER_DIR/expiry" ]]; then
			left=$(( $(cat "$TIMER_DIR/expiry") - $(now) ))
			(( left < 0 )) && left=0
			echo "$left" >"$TIMER_DIR/paused"
			rm -f "$TIMER_DIR/expiry"
		elif [[ -f "$TIMER_DIR/paused" ]]; then
			left="$(cat "$TIMER_DIR/paused")"
			echo $(( $(now) + left )) >"$TIMER_DIR/expiry"
			rm -f "$TIMER_DIR/paused"
		fi
		;;
	cancel)
		rm -rf "$TIMER_DIR"
		;;
	*)
		echo "usage: timer.sh status|start <mins>|pause|cancel" >&2
		exit 1
		;;
esac
