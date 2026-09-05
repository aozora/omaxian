# Settings

The Settings panel (`omaxian.settings`) is a tabbed editor for shell
configuration: bar layout, dock chrome, appearance tokens, widget options,
plugin enable/disable, and extra startup apps.

It is a first-party **panel** plugin (not a bar icon). Control Panel remains
the runtime picker for audio, Bluetooth, wallpaper gallery, theme, and
monitors.

Plugin path: `omaxian/.local/share/omarchy/shell/plugins/panels/settings/`
(deploys to `~/.local/share/omarchy/shell/plugins/panels/settings/`).

## Opening it

| From | How |
|---|---|
| Omarchy menu | Super+L → Setup → Settings |
| Control Panel | Gear icon → **Settings** at the bottom of the sidebar |
| Keybind | Super+Ctrl+S |
| IPC | `omarchy-shell shell toggle omaxian.settings` |
| Specific tab | `omarchy-shell shell summon omaxian.settings '{"tab":"bar"}'` |

Close with **Escape**, the **×** in the top-right corner, or the window
manager close binding. Settings is a real i3 floating window (title
`Omaxian Settings`), so it can be dragged from the title strip and resized.

Valid `tab` payload values: `bar`, `dock`, `appearance`, `widgets`, `plugins`,
`startup`, `advanced`.

## Tabs

### Bar

Writes `~/.config/omarchy/shell.json` (live). That user file is seeded once
by `deploy.sh` from `$OMARCHY_PATH/shell.json` and is **not** overwritten on
redeploy, so layout edits survive.

- Show / hide the bar (`omarchy-toggle-bar`, same as Menu → Toggle → Menu Bar)
- Position: top / bottom / left / right
- Transparent bar
- Center widget
- Per-section widget list with up / down / remove
- Available widgets that are not on the bar yet, with Add

### Dock

Writes `~/.config/omarchy/dock-settings.json` and toggles `omaxian.dock` via
`disabledPlugins`. Pinned apps stay on the dock (right-click / drag).

`fullWidth` may need `omarchy-restart-shell`; the other appearance flags apply
live.

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
Menu → Setup → Plugins.

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
`omarchy-startup-launch` runs at the end of `i3_autostart`. Session daemons
(dunst, picom, mpd, …) stay hardcoded and are not in this list.

### Advanced

Opens config files in the user’s editor (`omarchy-launch-config-editor`):
i3 keybindings, i3 theme/gaps, picom, dunst, menu extensions. Notes that
keyboard layout is `setxkbmap` in `i3_autostart` and that `idle.*` times in
`shell.json` are not enforced on X11.

## Reload

| Changed | Takes effect |
|---|---|
| `shell.json` (bar / widgets / plugins) | live (file-watched) |
| `shell.toml` | live (file-watched) |
| `dock-settings.json` roundedCorners / hoverAnimation | live |
| `dock-settings.json` fullWidth | `omarchy-restart-shell` |
| `startup.json` | next login, or Launch now |
