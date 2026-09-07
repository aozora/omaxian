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

# One watcher per login. pgrep -fc races on reload; flock does not.
watch_lock="${XDG_RUNTIME_DIR:-/tmp}/omaxian-display-watch.lock"
exec 9>"$watch_lock"
flock -n 9 || exit 0

last=$(display_state)
lock_flag="${XDG_RUNTIME_DIR:-/tmp}/omaxian-screen-locked"
changes=0

while sleep 2; do
	omarchy-session-is-i3 2>/dev/null || exit 0

	# i3_lock holds this while the locker is up. Applying xrandr mid-lock
	# (or the instant of unlock) has crashed Quickshell's I3 monitor refresh.
	if [[ -e $lock_flag ]]; then
		last=$(display_state)
		changes=0
		continue
	fi

	cur=$(display_state)
	if [[ $cur == "$last" ]]; then
		changes=0
		continue
	fi

	# Topology changing cycle after cycle means hardware is flapping or the
	# layout can't converge. Re-applying every 2s feeds a RandR event stream
	# that crashes Quickshell 0.3.0's I3 monitor refresh — back off until it
	# holds still.
	if (( ++changes > 3 )); then
		(( changes == 4 )) && echo "i3_display_watch: topology unstable — backing off" >&2
		last=$cur
		sleep 8
		continue
	fi

	omarchy-monitor-apply
	"$idir/scripts/i3_workspaces.sh"
	"$idir/scripts/i3_bar"

	# Re-sample after applying: omarchy-monitor-apply's own xrandr calls move
	# `xrandr --query`, so sampling before it guarantees a redundant re-apply
	# (and its RandR events) next cycle.
	last=$(display_state)
done
