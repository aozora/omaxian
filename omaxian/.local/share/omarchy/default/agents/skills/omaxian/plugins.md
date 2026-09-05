# Omaxian Shell: Bar, Dock, Plugins, and Idle

Read this before changing the status bar, dock, notifications, shell plugins,
widgets, or idle/lock behavior.

The bar, dock, settings panel, control panel, and assorted overlays all run
inside a single long-running Quickshell process (`omarchy-launch-shell`).
Notifications are **dunst**, not an Omarchy notification daemon.

```
~/.config/omarchy/shell.json             # User overrides: bar, plugins, idle
~/.config/omarchy/dock-settings.json     # Dock chrome
~/.config/omarchy/dock-pinned.json       # Pinned dock apps
~/.config/omarchy/plugins/<plugin-id>/   # User-owned shell plugins
~/.config/omarchy/shell.toml             # Appearance overrides (survives theme switch)
```

The shell hot-reloads `shell.json` on save — no restart needed for layout
changes. QML edits need `omarchy-restart-shell`.

Prefer the **Settings** window (Super+Ctrl+S) for bar layout, dock chrome,
widget options, plugin on/off, font/spacing, and extra startup apps. Prefer
**Control Panel** (Super+Ctrl+O) for audio, Bluetooth, wallpaper, theme, and
monitors.

**Commands:** `omarchy-restart-shell`, `omarchy-toggle-bar`

## Bar layout

Edit `~/.config/omarchy/shell.json` or use Settings → Bar. There is no
`omarchy bar move` dispatcher. The bar cannot be dragged to another screen;
change `bar.position` (`top` / `bottom` / `left` / `right`).

A valid `shell.json` (must contain `"version": 1`) **entirely replaces** the
bundled default at `$OMARCHY_PATH/shell.json` — there is no deep merge.
`./deploy.sh` seeds `~/.config/omarchy/shell.json` only when missing.

## Customizing built-in plugins and widgets

Never edit `$OMARCHY_PATH/shell/plugins/`. Clone into the user plugin
directory instead:

```bash
omarchy-plugin-clone omarchy.workspaces
# Edit ~/.config/omarchy/plugins/<username>.workspaces/; saved changes reload automatically.
```

Cloning switches the bar to the cloned copy, which survives `deploy.sh`.

Saving a file under `~/.config/omarchy/plugins/` reloads plugin code
automatically. If a change fails to apply: `omarchy-shell shell rescanPlugins`.

Community plugins are written for Arch + Hyprland. Before adding one:

```bash
omarchy-plugin-check <plugin-dir-or-git-url>
omarchy-plugin-add <git-url> --enable
```

## Dock

Plugin id `omaxian.dock`. Disable by adding it to `disabledPlugins` in
`shell.json`. Pinned apps: right-click / drag on the dock, or edit
`dock-pinned.json`.

## Idle and lock

`idle.screensaver` and `idle.lock` in `shell.json` are **not** wired to an
auto-locker in this port. Lock is Super+Ctrl+L / `omarchy-system-lock`
(`i3lock-fancy` or `i3lock`). Stay-awake on the bar toggles DPMS via `xset`.
