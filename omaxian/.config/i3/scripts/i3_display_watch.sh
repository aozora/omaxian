#!/usr/bin/env bash
## Re-apply display layout when lid state or monitor topology changes.

idir="$HOME/.config/i3"
: "${OMARCHY_PATH:=$HOME/.local/share/omarchy}"
case ":$PATH:" in *":$OMARCHY_PATH/bin:"*) ;; *) export PATH="$OMARCHY_PATH/bin:$PATH" ;; esac

# Bail if we somehow survive into a non-i3 session (e.g. leftover after DE switch).
if ! omarchy-session-is-i3 2>/dev/null; then
	exit 0
fi

display_state() {
	{
		xrandr --query 2>/dev/null
		for f in /proc/acpi/button/lid/LID*/state /sys/class/lid/LID*/state; do
			[[ -r "$f" ]] && cat "$f"
		done
	} | md5sum | awk '{ print $1 }'
}

# Avoid duplicate watcher from i3 reload
if [[ $(pgrep -fc 'i3_display_watch\.sh') -gt 1 ]]; then
	exit 0
fi

last=$(display_state)

while sleep 2; do
	omarchy-session-is-i3 2>/dev/null || exit 0

	cur=$(display_state)
	[[ "$cur" == "$last" ]] && continue

	omarchy-monitor-apply
	"$idir/scripts/i3_workspaces.sh"
	"$idir/scripts/i3_bar"

	last=$cur
done
