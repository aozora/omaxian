# Nag (Omaxian port)

Disposable alarms for the Omaxian bar. Port of
[jankeesvw/omarchy-nag](https://github.com/jankeesvw/omarchy-nag)
(upstream commit `fdf7314`).

Type `15:15 pick up the kids` into one field and it is set. The bar counts down
to it, turns red in the last five minutes, and keeps ringing until you answer.

Plugin id: `jankeesvw.nag` (unchanged). Optional — not installed by
`./deploy.sh`. See [`../README.md`](../README.md) for the catalog install
pattern.

## Omaxian deltas

| Upstream (Omarchy) | This port |
| ------------------ | --------- |
| Transient user calendar timers | Detached `setsid` sleeper (`nag-sleeper-<id>`), chunked wall-clock wait |
| Stop timer units by name | `pkill -f nag-sleeper-<id>` |
| `pw-play` only | `paplay` first, then `pw-play` |
| Hyprland bind example | i3 bind example below |

`Panel.qml` is unchanged: it already uses `KeyboardPanel` (X11-capable in
Omaxian) and has no Hyprland / layer-shell imports.

Alarms still live under `~/.local/state/nag` (0700). Sleepers do not survive a
reboot on their own; the next `list` / panel refresh re-arms any pending file
whose time is still ahead (same idea as upstream re-arming lost transient
units). After suspend, fire happens within about 30s of resume when the target
time has passed.

## Dependencies

`jq`, `dd`, `date` (GNU), `omarchy-notification-send`, and a player for
`/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga`
(`paplay` from pulseaudio-utils, or `pw-play`). Package
`sound-theme-freedesktop` provides the sound file.

## Install

From the Omaxian repo root:

```bash
PLUGIN=community-plugins/jankeesvw.nag
ID=$(jq -r .id "$PLUGIN/manifest.json")

omarchy-plugin-check "$PLUGIN"
omarchy-plugin-validate "$PLUGIN"

mkdir -p ~/.config/omarchy/plugins
rsync -a --delete -- "$PLUGIN/" "$HOME/.config/omarchy/plugins/$ID/"

omarchy-shell shell rescanPlugins
omarchy-plugin-enable "$ID"   # places the bar widget (default: right)
```

Or, once this tree is published as its own git repo:

```bash
omarchy-plugin-check https://github.com/…/omarchy-nag-omaxian.git
omarchy-plugin-add https://github.com/…/omarchy-nag-omaxian.git --enable
```

Open with `omarchy-shell shell toggle jankeesvw.nag`, or:

```bash
~/.config/omarchy/plugins/jankeesvw.nag/bin/nag ask
```

i3 keybind example (put in `~/.config/i3/config.d/` or similar):

```
bindsym $mod+n exec --no-startup-id $HOME/.config/omarchy/plugins/jankeesvw.nag/bin/nag ask
```

Menu extension (same as upstream), in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"nag": {
  "icon": "󰔟",
  "label": "Nag",
  "description": "Set a disposable alarm",
  "action": "$HOME/.config/omarchy/plugins/jankeesvw.nag/bin/nag ask"
}
```

## Remove

```bash
omarchy-plugin-remove jankeesvw.nag
~/.config/omarchy/plugins/jankeesvw.nag/bin/nag clear   # stops sleepers + deletes alarms
# or only wipe state if the plugin tree is already gone:
# rm -rf ~/.local/state/nag
```

## Licence

MIT — see [LICENSE](LICENSE). Upstream copyright Jankees van Woezik.
