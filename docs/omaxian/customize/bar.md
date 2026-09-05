# Customizing the Bar

How to change the bar's position, size, shape, colors, and widget layout.

The bar is the Quickshell plugin at
`omaxian/.local/share/omarchy/shell/plugins/bar/` (deploys to
`~/.local/share/omarchy/shell/plugins/bar/`). It reads three config layers plus
the QML itself:

| Layer | File (repo path → deployed path) | Controls | Reload |
|---|---|---|---|
| Stock defaults | `omaxian/.local/share/omarchy/shell.json` → `$OMARCHY_PATH/shell.json` | stock bar layout / idle / plugins; used when no user file exists | restart shell (or seed user file) |
| User layout | `~/.config/omarchy/shell.json` (seeded once by `deploy.sh`) | enable, position, transparency, which widgets, order, center anchor, per-widget settings | **live** (watched) |
| Theme tokens | `~/.local/state/omarchy/current/theme/{colors.toml,shell.toml}` | palette, bar thickness, bar background, control chrome | restart shell (read once at startup) |
| User override | `~/.config/omarchy/shell.toml` (create it) | same keys as theme `shell.toml`; wins over the theme and **survives theme switches** | **live** (watched) |
| Structure | `omaxian/.local/share/omarchy/shell/Commons/Style.qml` | corner radius, internal slot sizes | restart shell |

Restart the shell with `omarchy-restart-shell` after editing anything in the
theme's `colors.toml` / `shell.toml` or in the QML. The user `shell.json` and
`~/.config/omarchy/shell.toml` are file-watched and apply live.

> **No deep merge for `shell.json`.** A valid `~/.config/omarchy/shell.json`
> (must contain `"version": 1`) *entirely replaces* the bundled default at
> `$OMARCHY_PATH/shell.json`. Settings (Super+Ctrl+S) and hand edits write
> the user file; `./deploy.sh` seeds it only when missing, so redeploy does
> not wipe layout or Widgets options. To reset to stock: delete
> `~/.config/omarchy/shell.json` and re-run `./deploy.sh` (or restart the
> shell to fall back to defaults). See [settings.md](settings.md).

---

## Position

`~/.config/omarchy/shell.json`, `bar` block:

```json
"bar": {
  "enabled": true,
  "position": "top",
  "transparent": false,
  "centerAnchor": "omarchy.clock",
  "layout": { "...": "..." }
}
```

- **`position`** — `top` | `bottom` | `left` | `right`. `left`/`right` render a
  *vertical* bar (`Style.bar.sizeVertical` becomes its width; modules stack).
  Anything else falls back to `top`.
- **`enabled`** — set `false` to not render the bar at all.
- `position` also drives the strut reservation (windows tile around the bar) and
  the direction the bar slides when auto-hidden.

There is **no floating / detached / margin mode** — the bar is always a
full-width (or full-height) edge dock. Upstream's drag-to-move and floating
"ghost" bar were removed in this X11 port (see
`docs/omarchy-port/deltas.md`). "Shape" is therefore limited to *thickness* and
*internal corner rounding* (below).

## Transparency

`"transparent": true` in the `bar` block makes the bar background fully
transparent. The text/icon color is then auto-picked for contrast against the
wallpaper by `omarchy-bar-text-color` (re-sampled on wallpaper, position, or
theme change). `false` uses the solid `[bar] background` color from the theme.

## Size / thickness

Theme `shell.toml`, `[bar]` section (override in `~/.config/omarchy/shell.toml`
to make it permanent across theme switches):

```toml
[bar]
size-horizontal = 26     # height of a top/bottom bar   (at font base-size 12)
size-vertical   = 28     # width  of a left/right bar    (at font base-size 12)
scale-with-font = true   # when true, both scale with [font] base-size
```

Related global scalers:

```toml
[font]
base-size = 12           # rem root for all type; grows the bar when scale-with-font

[spacing]
scale = 1.0              # makes the whole shell (incl. bar padding/gaps) denser/roomier
scale-with-font = true
```

Internal bar slot sizes are **not** wired to `shell.toml` in this port — only
`size-horizontal`, `size-vertical`, and `scale-with-font` from `[bar]` are read
(`Style.qml` → `applyShellValues`). To change the rest, edit the `bar` block in
`Commons/Style.qml`:

| Token | Default | Meaning |
|---|---|---|
| `icon-slot` | 27 | icon-button widget slot size |
| `icon-canvas` | 16 | drawn icon box inside a slot |
| `icon-font` | 13 | glyph point size |
| `status-slot` | 21 | status/indicator slot size |

## Shape / corner rounding

`Commons/Style.qml` — static literals in this port (upstream syncs them live
from `hyprctl`; there is no compositor sync on i3/X11):

```qml
property int cornerRadius: 8    // bar chips, workspace pills, generic Ui/ controls
property int radiusPopup: 12    // popup cards opened from the bar
property int gapsOut: 8         // gap between a popup and the bar edge
```

Workspace pills, the panel-open indicator marks, hover fills, etc. all derive
their radius from `Style.cornerRadius`. Edit here and restart the shell.

## Colors

### Foundational palette — theme `colors.toml`

```toml
background = "#060B1E"   # bar background base
foreground = "#ffcead"   # bar text / icons
accent     = "#7d82d9"   # menu logo, active workspace, selection
muted      = "#6d7db6"
red        = "#ED5B5A"   # mapped to the "urgent" role
```

Read once at startup by `Commons/Color.qml` → restart the shell after editing.

### Bar surface — theme `shell.toml` `[bar]` (or `~/.config/omarchy/shell.toml`)

```toml
[bar]
background       = "#060B1E"
background-alpha = 1.0        # e.g. 0.85 for a translucent solid bar
```

`Commons/Color.qml` also exposes `bar.text` and `bar.active` (falls back to
`foreground` / `urgent` when unset).

### Per-widget accent colors — `Services/BarPalette.qml`

Widget color-coding (mpd = green, weather = yellow, vpn on/off, sysstats chip,
and the workspace focused / visible / urgent states) is defined in
`omaxian/.local/share/omarchy/shell/Services/BarPalette.qml`, which reads these
named keys from the theme's `colors.toml`:

```
red  orange  yellow  green  cyan  blue  magenta  brown
selection  lighter_background  dark_foreground
```

To recolor a widget: change the relevant named key in the theme's `colors.toml`,
or edit the fallback value / mapping in `BarPalette.qml` (the `property color`
block near the top, and the `bar surface vocabulary` / `workspace` blocks
below).

### Interactive chrome — theme `shell.toml` `[controls]`

Borders and hover/focus fills on bar buttons and the shared `Ui/` kit:
`normal-border`, `normal-border-width`, `hover-cursor-border-alpha`,
`focus-border-width`, `selected-border`, etc.

## Widgets: which, where, and in what order

`shell.json` → `bar.layout` has three ordered arrays. Add / remove / reorder the
entries to change the bar:

```json
"layout": {
  "left":   [ { "id": "omaxian.menu" }, { "id": "omarchy.workspaces" }, { "id": "omaxian.mode" } ],
  "center": [ { "id": "omaxian.media" }, { "id": "omarchy.clock" } ],
  "right":  [
    { "id": "omaxian.controlpanel" }, { "id": "omarchy.weather" },
    { "id": "omaxian.sysstats" }, { "id": "omarchy.keyboard-layout" },
    { "id": "omarchy.network" }, { "id": "omaxian.vpn" }, { "id": "omaxian.updates" },
    { "id": "omaxian.notifications" }, { "id": "omaxian.help" },
    { "id": "omarchy.indicators" }, { "id": "omarchy.tray" },
    { "id": "omarchy.power" }, { "id": "omaxian.powermenu" }
  ]
}
```

- **Remove** an entry → that widget disappears.
- **Reorder** entries → left section fills left-to-right, right section fills
  right-to-left, center is balanced around the anchor.
- **`centerAnchor`** — the widget id that stays pinned to the exact screen
  center; the rest of the `center` array flows out to either side of it.
- **Per-widget settings** — any extra keys on a layout entry beyond `id` are
  passed to that widget as inline settings, e.g.
  `{ "id": "omarchy.clock", "format": "dddd HH:mm" }`. Changing only inline
  settings patches the running widget in place without rebuilding the bar.
- **Spacers** — use `omarchy.spacer` entries to push groups apart.
- **Disable a whole plugin** — add its id to the top-level `disabledPlugins`
  array (e.g. `omarchy.polkit` is disabled there today). A plugin counts as
  "enabled" as soon as its id appears anywhere in `shell.json`.

### Available widget ids

Built-ins (`omarchy.*`):

```
omarchy.workspaces  omarchy.clock  omarchy.weather  omarchy.network
omarchy.tray  omarchy.power  omarchy.indicators  omarchy.keyboard-layout
omarchy.microphone  omarchy.audio  omarchy.bluetooth  omarchy.spacer
omarchy.system-update  omarchy.reminders  omarchy.nightlight
```

Omaxian widgets (`omaxian.*`, port-authored — see `docs/omarchy-port/deltas.md`):

```
omaxian.menu  omaxian.mode  omaxian.media  omaxian.controlpanel
omaxian.sysstats  omaxian.vpn  omaxian.updates  omaxian.notifications  omaxian.help
omaxian.powermenu  omaxian.wallpapers  omaxian.themes  omaxian.dock  omaxian.monitor
```

`local.mpd` is retired — MPD shows up in `omaxian.media` through `mpDris2`.
`omarchy.keyboard-layout` click cycles the XKB group (`xkb-switch` /
`ISO_Next_Group` / `setxkbmap`).

## Applying changes

| Changed | How it takes effect |
|---|---|
| `~/.config/omarchy/shell.json` | live (file-watched) |
| `~/.config/omarchy/shell.toml` | live (file-watched) |
| Theme `colors.toml` / `shell.toml` | `omarchy-restart-shell` |
| `Commons/Style.qml`, `Services/BarPalette.qml`, any `.qml` | `omarchy-restart-shell` |
| System font (`omarchy-font-set`) | live (resolved via fontconfig at paint time) |
