# Customizing the Dock

How to change the dock's width mode, corners, size, colors, indicators,
autohide, and pinned apps.

See `docs/omarchy-port/dock.md` for the design/behaviour writeup. This page is
the customization surface only.

The dock is the Quickshell plugin at
`omaxian/.local/share/omarchy/shell/plugins/panels/dock/` (deploys to
`~/.local/share/omarchy/shell/plugins/panels/dock/`), plugin id `omaxian.dock`.
It is a `panel`-kind, `keepLoaded` plugin — auto-mounted at startup, **no
`shell.json` layout entry**.

| Layer | File | Controls | Reload |
|---|---|---|---|
| Theme | `themes/<name>/dock.toml` → `current/theme/dock.toml` | all appearance keys for that theme | live (watched) / theme switch |
| User overlay | `~/.config/omarchy/dock.toml` | sparse overrides; **survives theme switches** (Settings → Dock) | live |
| Legacy | `~/.config/omarchy/dock-settings.json` | used only if user `dock.toml` is missing | live |
| Pinned apps | `~/.config/omarchy/dock-pinned.json` | which apps are pinned, and their order | in-app right-click/drag is live; external edits need a restart |

Merge order: **defaults ← theme `dock.toml` ← user `dock.toml`** (or legacy JSON).
Empty `background` matches the **bar** fill (`Color.bar.background`).

Example theme file: `$OMARCHY_PATH/default/omarchy/dock.toml.example`.

## Disable the dock

Add its id to the top-level `disabledPlugins` array in
`~/.config/omarchy/shell.json`:

```json
"disabledPlugins": ["omarchy.polkit", "omaxian.dock"]
```

---

## Appearance — theme / user `dock.toml`

```toml
[dock]
full-width = true
hover-animation = true
background = ""              # empty = match bar background
opacity = 1.0                # 1 = opaque
icon-size = 36
hover-scale = 1.3
corner-radius = 0            # used when full-width is false
island-gap = 0               # padding around the pill (like bar island)
running-indicator = "dot"    # dot | bar | none
auto-hide = false
```

| Key | Default | Effect |
|---|---|---|
| `full-width` | `true` | Full edge vs centered pill (pill remainder is click-through) |
| `hover-animation` | `true` | Enable hover magnification |
| `background` | `""` | Pill `#rgb` / `#rrggbb`; empty uses bar background |
| `opacity` | `1` | Pill opacity (`0`–`1`); icons stay opaque |
| `icon-size` | `36` | Icon pixel size (dock thickness follows) |
| `hover-scale` | `1.3` | Magnification factor when hover animation is on (`1`–`2`) |
| `corner-radius` | `0` | Pill corner radius when not full-width |
| `island-gap` | `0` | Outer padding (px) around the chrome; wallpaper shows through |
| `running-indicator` | `"dot"` | `dot`, `bar` (underline), or `none` |
| `auto-hide` | `false` | Park off the bottom edge; reveal on hover |

Settings → Dock writes sparse keys into `~/.config/omarchy/dock.toml`.
`full-width` / strut-affecting size changes may need `omarchy-restart-shell`.

## Pinned apps — `~/.config/omarchy/dock-pinned.json`

```json
{
  "pinned": ["dev.zed.Zed", "org.kde.dolphin"]
}
```

A flat, ordered array of desktop-entry ids. Manage from the dock:

- **Right-click** → toggle pinned
- **Long-press** (450 ms) → edit mode; **drag** to reorder

Running (unpinned) apps append after pinned ones automatically.

## Applying changes

| Changed | How it takes effect |
|---|---|
| Theme / user `dock.toml` (most keys) | live (file-watched) |
| `full-width` / large size changes | `omarchy-restart-shell` recommended |
| `dock-pinned.json` via dock UI | live |
| `dock-pinned.json` hand-edited | `omarchy-restart-shell` |
| `Panel.qml` / `Model.js` | `omarchy-restart-shell` |
