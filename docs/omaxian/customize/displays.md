# Displays and workspaces

How Omaxian treats **multiple monitors** (different resolutions, lid close,
plug/unplug) and **i3 workspaces** across those outputs.

This is X11 + i3 + xrandr. There is no Hyprland fractional scaling, no
`hyprpaper`, and no per-output Wayland background layer.

## What i3 actually does

Workspaces are a **single global 1–10 list**. Each output shows exactly one
of them. Super+4 does not mean “workspace 4 on this screen” — it means “go
to wherever 4 currently lives,” which may be the other monitor.

| Term | Meaning |
|---|---|
| Focused | The workspace that has keyboard focus (square glyph on the bar) |
| Active / visible | Shown on some output (softer pill on the bar when it is not focused) |
| Occupied | Exists (has been created); dim numbers are unused slots 1–10 |

The bar is spawned **once per monitor**. Both bars show the same 1–10 row.
Clicks are hit-tested only against widgets on that bar’s window (a point on
the laptop bar must not activate a widget on the HDMI bar).

## Display layout (resolution, position, lid)

Control Panel → Monitor (`Super+Ctrl+D`), or:

```bash
omarchy-monitor-list
omarchy-monitor-set <output> <mode>|--off|--primary|--left-of …
omarchy-monitor-apply
```

`omarchy-monitor-apply` restores the last layout for the current **topology
signature** (which outputs are connected, including “laptop lid closed”).
Profiles live in `~/.local/state/omarchy/monitor/profiles.json`. A fallback
for an unseen topology is: preferred mode on each output, chained `--right-of`,
last output primary. Laptop panel is dropped when the lid is closed and
another output remains.

Different native resolutions are normal (e.g. 1920×1200 laptop + 1920×1080
HDMI). i3 and the bar use each output’s pixel size; there is no per-monitor
UI scale. xrandr `--scale` is not wired into the panel.

`i3_display_watch.sh` re-runs `omarchy-monitor-apply` when RandR or lid
state changes, then restarts the bar launcher. After apply, workspaces are
**left where i3 put them** — workspace 1 is not forced onto the primary
(that used to steal it from the other monitor).

`omarchy-monitor-apply` runs **at login** (`exec`, not `exec_always`). An
`i3-msg reload` must not re-modeset the outputs — that blanks both screens
and looks like a session crash. Hotplug is the watcher; Control Panel still
calls apply/set when you change a layout.

## Workspace keys

Stay on the **current output** unless noted.

| Key | Action |
|---|---|
| Super+1…0 | Focus that workspace wherever it lives (may change monitor) |
| Super+Tab / Super+Shift+Tab | Next / previous workspace **on this output** |
| Super+Ctrl+Tab | Last-used workspace (global back-and-forth) |
| Super+scroll | Same as Super+Tab / Shift+Tab (this output) |
| Super+Shift+1…0 | Move window to that workspace and follow |
| Super+Shift+Alt+1…4 | Move window there, do not follow |
| Super+Ctrl+Left / Right | Carry window to prev/next workspace on this output and follow |
| Ctrl+Alt+Tab | Focus the next **output** |
| Super+Alt+arrows | Move the focused **window** to the adjacent output |
| Super+Ctrl+Alt+arrows | Move the whole **workspace** to the adjacent output |

## Bar clicks

On the workspace row of a given bar:

| Click | Action |
|---|---|
| Left | Focus that number **on this output**. If it currently lives on the other monitor, i3 **pulls the workspace here**, then focuses it. If it does not exist yet, it is created here. |
| Shift+left or middle | Super+N behaviour: only focus, even if that jumps to the other monitor |

The square pill is the focused workspace; a second pill is the workspace
visible on the other output.

## Pinning 1–5 / 6–10 (optional)

i3 can create new workspaces on a named output if you pin them in config.
Output names (`eDP`, `HDMI-A-0`, …) change with docks and GPUs, so the
stock tree does **not** ship pins.

To keep 1–5 on the laptop and 6–10 on the external, add a **local** file
that `./deploy.sh` will not overwrite (it only replaces files that exist in
the repo):

`~/.config/i3/config.d/90_outputs.conf`

```
# Names from `omarchy-monitor-list` / `xrandr --query`
workspace 1 output eDP
workspace 2 output eDP
workspace 3 output eDP
workspace 4 output eDP
workspace 5 output eDP
workspace 6 output HDMI-A-0
workspace 7 output HDMI-A-0
workspace 8 output HDMI-A-0
workspace 9 output HDMI-A-0
workspace 10 output HDMI-A-0
```

Then `i3-msg reload`. Super+1…5 then create/focus on the laptop even if the
external is focused. Super+6…0 stay on the HDMI. You can still **move** a
workspace across with Super+Ctrl+Alt+arrows or by left-clicking its number
on the other bar.

Do not invent a second 1–10 strip per monitor (Hyprland-style). i3 cannot
do that without renaming workspaces, which would break Super+1…0.

## Wallpaper

`omarchy-theme-bg-set` / `~/.config/i3/wallpaper.sh` paint **one** image on
the X root with `hsetroot -cover` (then `feh --bg-fill`, then
`xwallpaper --zoom`). That is a single pixmap for the whole virtual desktop,
not a separate file per output. A 16:10 laptop plus a 16:9 HDMI will crop
the same file differently on each screen.

Per-output images would need a setter that talks to each RandR output
(e.g. `feh --no-xinerama` with one file per screen, or `nitrogen`). That is
not wired yet. The picker in Control Panel still chooses one path and
updates `~/.local/state/omarchy/current/background`.

Theme backgrounds ship several pixel sizes under
`themes/<name>/backgrounds/` (1920×1080, 2560×1440, 3440×1440, …). Pick the
size closest to your **largest** output; `-cover` fills the rest.

## Related

- [bar.md](bar.md) — bar layout, island chrome, strut
- [settings.md](settings.md) — Settings window
- `./deploy.sh` on a live session must use rsync (not `cp -r`); see the
  install-scripts agent guide. `i3-msg reload` is config-only (no xrandr,
  no autostart, no picom restart). Do not chain `omarchy-restart-shell`.
- Control Panel Monitor tab: `omaxian/.local/share/omarchy/shell/plugins/panels/controlpanel/MonitorTab.qml`
- Workspace widget: `omaxian/.local/share/omarchy/shell/plugins/bar/widgets/Workspaces.qml`
