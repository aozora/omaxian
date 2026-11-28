#!/bin/bash

# Print dunst's state and history as one JSON object, for the bar's
# notification panel. `now` is on the clock dunst stamps notifications with
# (monotonic microseconds). Text is bounded: any app can send any amount.

set -euo pipefail

# dunstctl would D-Bus-activate a stopped dunst, with its other config, racing
# the i3 script that restarts it. So only ask while something owns the name.
owned=$(gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
  --method org.freedesktop.DBus.NameHasOwner org.freedesktop.Notifications)
[[ $owned == "(true,)" ]] || exit 1

paused=$(dunstctl is-paused)
waiting=$(dunstctl count waiting)
history=$(dunstctl history)
now=$(python3 -I -c 'import time; print(time.monotonic_ns() // 1000)')

jq -c --argjson paused "$paused" --argjson waiting "$waiting" --argjson now "$now" '
  {
    paused: $paused,
    waiting: $waiting,
    now: $now,
    entries: [.data[0][] | {
      id: .id.data,
      ts: .timestamp.data,
      app: (.appname.data // "")[0:100],
      summary: (.summary.data // "")[0:300],
      body: (.body.data // "")[0:2000],
      urgency: (.urgency.data // "NORMAL"),
      icon: (.icon_path.data // "")
    }]
  }' <<<"$history"
