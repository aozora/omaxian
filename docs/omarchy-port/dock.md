# Dock

A persistent bottom dock plugin: pinned app launcher with a running-app
indicator, macOS-style hover magnification, and drag-to-reorder. Scoped-down
port of [rosakodu/omarchy-dock](https://github.com/rosakodu/omarchy-dock)
(built for upstream Omarchy Quattro on Hyprland/Wayland) to this Devuan/i3/X11
profile — see `docs/omarchy-port/deltas.md`'s general porting conventions for
context on why a straight port wasn't possible.

Plugin id `omaxian.dock`, files under
`omaxian/.local/share/omarchy/shell/plugins/panels/dock/`:

- `manifest.json` — `kinds: ["panel"]`, `keepLoaded: true`. Auto-loaded by
  `shell.qml`'s panel Loader at startup; first-party `panel`-kind plugins are
  enabled by default, so there's no `shell.json` entry to manage. To disable
  it, add `"omaxian.dock"` to `shell.json`'s `disabledPlugins[]`.
- `Panel.qml` — one `PanelWindow` per screen (`Variants` over
  `Quickshell.screens`, same shape as `plugins/bar/Bar.qml`), anchored to the
  bottom edge with `exclusionMode: ExclusionMode.Auto` — i3 reserves real
  strut space, so windows tile above it, the same way they already do above
  the top bar. Deliberately **no** `aboveWindows` override: a fullscreen
  window covers the dock instead of the dock floating above it (the opposite
  of upstream's Hyprland-layer-shell "always on top" dock).
- `Model.js` — pure functions: pinned-list persistence
  (`parsePinned`/`serializePinned`/`togglePinned`), settings persistence
  (`parseSettings`/`serializeSettings`), and window↔desktop-entry matching
  (`entryForWindow`, keyed primarily off `DesktopEntry.startupClass` i.e.
  `StartupWMClass`, falling back to normalized id/exec-basename). A fraction
  of upstream's `DockPinned.js`/`DockMatcher.js` — no stacks/folders, no
  CLI/web-app/brand heuristics.
- `Services/I3Windows.qml` (shell-wide singleton, `qs.Services`, not part of
  the dock plugin itself) — the live window list `Quickshell.I3` doesn't
  provide on its own. Seeded once via `i3-msg -t get_tree`, kept live via
  `I3IpcListener { subscriptions: ["window", "workspace"] }` (in-process i3
  IPC events, no polling). Exposes `windows[]` (`{conId, appId, title,
  workspace, focused, urgent}`) and `focusWindow(conId)`.

## Interacting with it

- **Click** a pinned-but-not-running icon → launches it
  (`AppLibrary.launch()`). Click a running icon → focuses its most recently
  focused window (`I3Windows.focusWindow()`).
- **Right-click** any icon → toggle pinned. Persists immediately to
  `dock-pinned.json`.
- **Long-press** (450ms) any icon → enters edit mode: pinned icons get an
  accent-colored border and become draggable; unpinned icons dim. No wiggle
  animation (deliberately dropped — see `TODO.md`).
- **Drag** a pinned icon while in edit mode → reorders the pinned list live;
  drop to persist.
- **Tap the empty dock background** while in edit mode → exits edit mode.
- **Hover** an icon (outside edit mode) → scales up 1.3x from the bottom
  edge, if `hoverAnimation` is on.

## Settings — `~/.config/omarchy/dock-settings.json`

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
| `fullWidth` | `true` | `true`: dock spans the whole screen edge (original MVP look). `false`: shrinks to a centered pill sized to its icons; the rest of the reserved strut width is fully click-through (desktop shows through, nothing intercepts clicks/hover there). |
| `roundedCorners` | `false` | Only visible when `fullWidth` is `false`. Rounds the pill's corners (`Style.radiusPopup`, matching this shell's other floating surfaces) instead of square corners. |
| `hoverAnimation` | `true` | macOS-style scale-up-on-hover (see above). |

**Reload behavior differs by field**: `roundedCorners` and `hoverAnimation`
apply live — the settings file is watched (`watchChanges: true`) and there's
no in-app writer racing it, unlike the pinned-list file (see below). Changing
`fullWidth` was only verified after a full restart during development, so run
`omarchy-restart-shell` after changing it rather than relying on the live
watch.

Malformed or missing fields fall back to their defaults individually (a
partial JSON object is fine); a missing or unparsable file falls back to all
defaults.

## Pinned apps — `~/.config/omarchy/dock-pinned.json`

```json
{
  "pinned": ["dev.zed.Zed", "org.kde.dolphin"]
}
```

A flat, ordered array of desktop-entry ids (no stacks/folders). Normally
managed via right-click/drag in the dock itself, not hand-edited. Written
with `FileView.setText()`, deliberately **not** watched live
(`watchChanges` is off) — an earlier version watched it, and the dock's own
write would race its own watcher's re-read, occasionally losing a pin/unpin
that landed a moment earlier. An external hand-edit to this file only takes
effect on the next `omarchy-restart-shell`.

## Known limitations (by design, for this MVP)

- No app stacks/folders, no multi-instance window cycling (multiple windows
  of a pinned app: clicking focuses whichever was most recently focused).
- No autohide/hover-reveal visibility modes — always visible.
- No notification badges.
- Dynamic "position opposite the bar" isn't implemented — the dock is
  hardcoded to the bottom edge (this profile's bar defaults to `top`, so
  there's no conflict).

See `TODO.md` and `docs/omarchy-port/deltas.md` for the broader porting
context this plugin was built against.
