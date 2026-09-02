# Customizing the Dock

How to change the dock's width mode, corners, hover animation, size, colors, and
pinned apps.

See `docs/dock.md` for the full design/behaviour writeup. This page is the
customization surface only.

The dock is the Quickshell plugin at
`omaxian/.local/share/omarchy/shell/plugins/panels/dock/` (deploys to
`~/.local/share/omarchy/shell/plugins/panels/dock/`), plugin id `omaxian.dock`. It
is a `panel`-kind, `keepLoaded` plugin — auto-mounted at startup, **no
`shell.json` layout entry**. It reads two hand-editable JSON files plus the
QML itself:

| Layer | File | Controls | Reload |
|---|---|---|---|
| Appearance | `~/.config/omarchy/dock-settings.json` | width mode, corners, hover animation | live for `roundedCorners`/`hoverAnimation`; restart for `fullWidth` |
| Pinned apps | `~/.config/omarchy/dock-pinned.json` | which apps are pinned, and their order | in-app right-click/drag is live; external edits need a restart |
| Theme tokens | `~/.local/state/omarchy/current/theme/{colors.toml,shell.toml}` | pill color, accent dot, and (via `[spacing]`/`[font]`) overall scale | `omarchy-restart-shell` |
| Structure | `plugins/panels/dock/Panel.qml` | dock thickness, icon size, spacing, magnification factor, dot size, position | `omarchy-restart-shell` |

Restart with `omarchy-restart-shell` after editing the theme files or the QML.

## Disable the dock

Add its id to the top-level `disabledPlugins` array in
`~/.config/omarchy/shell.json`:

```json
"disabledPlugins": ["omarchy.polkit", "omaxian.dock"]
```

---

## Appearance — `~/.config/omarchy/dock-settings.json`

Hand-edited JSON, defaults shown:

```json
{
  "fullWidth": true,
  "roundedCorners": false,
  "hoverAnimation": true
}
```

| Field | Default | Effect |
|---|---|---|
| `fullWidth` | `true` | `true`: the dock pill spans the whole screen edge. `false`: it shrinks to a centered pill sized to its icons (`max(dockSize, iconRow.width + 24px)`); the rest of the reserved strut is masked click-through so it doesn't swallow input meant for windows above it. |
| `roundedCorners` | `false` | Only takes visible effect when `fullWidth` is `false`. Rounds the pill corners to `Style.radiusPopup` (12, matching the shell's other floating surfaces) instead of square. |
| `hoverAnimation` | `true` | macOS-style scale-up (1.3×, growing from the bottom edge) on the hovered icon. |

Missing/malformed fields fall back to their defaults individually; a
missing/unparsable file falls back to all defaults.

**Reload behaviour:** the file is watched (`watchChanges: true`) with no in-app
writer, so `roundedCorners` and `hoverAnimation` apply live. `fullWidth` was
only verified across a full restart during development — run
`omarchy-restart-shell` after changing it.

## Pinned apps — `~/.config/omarchy/dock-pinned.json`

```json
{
  "pinned": ["dev.zed.Zed", "org.kde.dolphin"]
}
```

A flat, ordered array of desktop-entry ids (the `.desktop` basename, with or
without the extension). Order in the array = order on the dock. No
stacks/folders.

Normally you don't hand-edit this — manage it from the dock:

- **Right-click** any icon → toggle pinned (persists immediately).
- **Long-press** (450 ms) any icon → edit mode; **drag** pinned icons to
  reorder (persists on drop); tap the empty dock background to exit.

This file is deliberately **not** watched (an earlier version raced its own
write-back and lost pins). A hand-edit only takes effect on the next
`omarchy-restart-shell`.

Running (unpinned) apps are appended after the pinned ones automatically, matched
to a desktop entry by `StartupWMClass` → normalized desktop-id → exec basename
(`Model.js` → `entryForWindow`). Icons come from the matched `.desktop` entry.

## Colors — theme `colors.toml`

The dock has no dedicated color tokens in `shell.toml`; it uses the foundational
palette from the active theme's `colors.toml`:

| Element | Token | `Panel.qml` |
|---|---|---|
| Pill background | `background` | `pillBackground.color: Color.background` |
| Running-app dot | `accent` | `color: ... Color.accent` |
| Running-app dot, urgent window | `red` (→ `urgent` role) | `color: cell.modelData.urgent ? Color.urgent : ...` |
| Edit-mode border on draggable icons | `accent` | `border.color: Color.accent` |

Change these in the theme's `colors.toml` and restart the shell. To give the
dock its own colors independent of the theme, edit the bindings above in
`Panel.qml`.

## Size, spacing, magnification, position — `Panel.qml`

These are not exposed as config. Edit
`omaxian/.local/share/omarchy/shell/plugins/panels/dock/Panel.qml` and restart.

| What | Where | Default |
|---|---|---|
| Dock thickness / reserved strut height | `readonly property int dockSize` | `Style.space(56)` |
| Icon size | `readonly property int iconSize` | `Style.space(36)` |
| Gap between icons | `iconRow.cellStep` | `iconSize + Style.space(10)` |
| Pill horizontal padding (non-full-width) | `pillBackground.width` | `iconRow.width + Style.space(24)` |
| Hover magnification factor | `cell.scale` | `1.3` |
| Hover animation timing | `Behavior on scale` | `120 ms`, `Easing.OutBack` |
| Running-dot size | inner `Rectangle.width/height` | `Style.space(6)` |
| Running-dot offset below icon | `anchors.bottomMargin` | `-Style.space(6)` |
| Edit-mode border width / radius | edit-affordance `Rectangle` | `max(1, Style.space(2))` / `Style.cornerRadius` |
| Long-press threshold for edit mode | `longPressTimer.interval` | `450` ms |
| Non-full-width pill grow/shrink timing | `Behavior on width` | `150 ms`, `Easing.OutCubic` |

**Position is hard-coded to the bottom edge**
(`anchors { bottom: true; left: true; right: true }`). There is no
"opposite the bar" logic — this profile's bar defaults to `top`, so there's no
conflict. To move the dock, change those anchors and `implicitHeight` →
`implicitWidth`.

`exclusionMode: ExclusionMode.Auto` reserves real strut space (i3 tiles windows
above the dock). There is deliberately **no** `aboveWindows` override: a
fullscreen window covers the dock rather than the dock floating over it.

### Overall scale via the theme

Every size above goes through `Style.space()`, which multiplies by
`[spacing] scale` × the `[font] base-size` font scale (when
`scale-with-font = true`). So bumping either of these in the theme's
`shell.toml` (or `~/.config/omarchy/shell.toml`) scales the whole dock
proportionally without touching `Panel.qml`:

```toml
[spacing]
scale = 1.0            # 1.2 → dock, icons, gaps all ~20% bigger
scale-with-font = true

[font]
base-size = 12
```

## Applying changes

| Changed | How it takes effect |
|---|---|
| `dock-settings.json` → `roundedCorners`, `hoverAnimation` | live (file-watched) |
| `dock-settings.json` → `fullWidth` | `omarchy-restart-shell` |
| `dock-pinned.json` via right-click / drag in the dock | live |
| `dock-pinned.json` hand-edited | `omarchy-restart-shell` |
| Theme `colors.toml` / `shell.toml` | `omarchy-restart-shell` |
| `Panel.qml` / `Model.js` | `omarchy-restart-shell` |
