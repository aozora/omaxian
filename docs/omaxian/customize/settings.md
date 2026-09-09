# Settings

The Settings panel (`omaxian.settings`) is a tabbed editor for shell
configuration: bar layout, dock chrome, appearance tokens, widget options,
plugin enable/disable, keyboard layouts, and extra startup apps.

It is a first-party **panel** plugin (not a bar icon). Control Panel remains
the runtime picker for audio, Bluetooth, wallpaper gallery, theme, and
monitors.

Plugin path: `omaxian/.local/share/omarchy/shell/plugins/panels/settings/`
(deploys to `~/.local/share/omarchy/shell/plugins/panels/settings/`).

## Opening it

| From | How |
|---|---|
| Omarchy menu | Super+Space → Setup → Settings |
| Control Panel | Gear icon → **Settings** at the bottom of the sidebar |
| Keybind | Super+Ctrl+S |
| IPC | `omarchy-shell shell toggle omaxian.settings` |
| Specific tab | `omarchy-shell shell summon omaxian.settings '{"tab":"bar"}'` |

Close with **Escape**, the **×** in the top-right corner, or the window
manager close binding. Settings is a real i3 floating window (title
`Omaxian Settings`), so it can be dragged from the title strip and resized.

Valid `tab` payload values: `bar`, `dock`, `appearance`, `widgets`, `plugins`,
`startup`, `keyboard`, `advanced`.

## Tabs

### Bar

Writes `~/.config/omarchy/shell.json` (live). That user file is seeded once
by `deploy.sh` from `$OMARCHY_PATH/shell.json` and is **not** overwritten on
redeploy, so layout edits survive.

- Show / hide the bar (`omarchy-toggle-bar`, same as Menu → Toggle → Menu Bar)
- Position: top / bottom / left / right
- Transparent bar
- Floating island (`island`, `islandMargin`, `islandRadius`) — inset rounded
  chrome; see [bar.md](bar.md). Toggling island may need a shell reload
  (prefer log out / log in; avoid `omarchy-restart-shell` on glx picom)
- Dual-pane arrange UI: **Available** (left) and **Left / Center / Right**
  lists (right). Drag the ⠿ handle to reorder within a section, move across
  sections, add from Available, or drop onto Available to remove. ▲ / ▼ / ×
  remain as click fallbacks. **Add** opens a Left / Center / Right picker
  (default section from the widget manifest is highlighted)

### Dock

Writes sparse overrides to `~/.config/omarchy/dock.toml` (survives theme
switches) and toggles `omaxian.dock` via `disabledPlugins`. Theme defaults come
from `dock.toml` in the active theme. Pinned apps stay on the dock
(right-click / drag).

- Show dock / full width / hover magnification / autohide
- Background color (empty = match bar; Pick via `gpick`) and opacity
- Icon size, hover scale, corner radius, island gap
- Running indicator: dot / bar / none

`full-width` may need a shell reload (prefer log out / log in); most other
keys apply live.

### Appearance

Writes `~/.config/omarchy/shell.toml` (user override, survives theme switches;
already file-watched):

- UI font size (`[font] base-size`)
- UI density (`[spacing] scale`)
- Bar height / width (`[bar] size-horizontal` / `size-vertical`)
- Extra wallpaper folder (`wallpaper-settings.json` `localFolder`)
- Buttons that open Control Panel’s wallpaper / theme pickers

### Widgets

Schema-driven forms for bar widgets that declare `barWidget.schema` in their
manifest (clock, weather, power, spacer, menu icon, indicators, …). Values
land on the layout entry in `~/.config/omarchy/shell.json`. A widget must be
on the bar for changes to persist. Like Bar edits, these survive `./deploy.sh`.

### Plugins

Enable / disable first-party panels and services, plus third-party plugins
under `~/.config/omarchy/plugins/`. Add / clone / remove still lives under
Menu → Setup → Plugins. Optional Omaxian-compatible ports (not deployed by
default) are catalogued in the repo under
[`community-plugins/`](../../../community-plugins/README.md).

Settings itself cannot be disabled from this list.

### Startup

Extra login apps in `~/.config/omarchy/startup.json`:

```json
{
  "apps": [
    { "desktopId": "brave", "enabled": true }
  ]
}
```

Add from the app catalog, enable / disable, reorder, remove, or **Launch now**.
`omarchy-startup-launch` runs at the end of `i3_autostart` and waits until the
bar's StatusNotifier host is up so Qt tray apps (Flameshot, MEGAsync, …) can
register a systray icon. Session daemons (dunst, picom, mpd, …) stay hardcoded
and are not in this list.

### Keyboard

XKB layouts in `~/.config/omarchy/keyboard.json` (not overwritten by deploy):

```json
{
  "layouts": [
    { "layout": "it", "variant": "" },
    { "layout": "ru", "variant": "phonetic" }
  ],
  "toggle": "grp:alt_shift_toggle"
}
```

Add / remove / reorder layout rows, pick a toggle shortcut (Alt+Shift by
default so Super+Space stays free for the menu), and **Apply now**.
`omarchy-keyboard-apply` runs at login from `i3_autostart`. If the file is
missing, the same defaults as above are used.

### Advanced

Opens config files in the user’s editor (`omarchy-launch-config-editor`):
i3 keybindings, i3 theme/gaps, picom, dunst, menu extensions. Notes that
keyboard layouts live under Settings → Keyboard / `keyboard.json`, and that
`idle.*` times in `shell.json` are not enforced on X11.

## Reload

| Changed | Takes effect |
|---|---|
| `shell.json` (bar / widgets / plugins) | live (file-watched) |
| `shell.json` `island` toggle | often needs log out / log in |
| `shell.toml` | live (file-watched) |
| Theme / user `dock.toml` | live |
| `dock.toml` `full-width` | often needs log out / log in |
| `startup.json` | next login, or Launch now |
| `keyboard.json` | next login, or Apply now |

Do not use `omarchy-restart-shell` to apply those reload cases on a glx
picom session — it can freeze X. Log out and back in instead.

See also [displays.md](displays.md) for multi-monitor layout, workspace
clicks, and wallpaper-on-X11.
