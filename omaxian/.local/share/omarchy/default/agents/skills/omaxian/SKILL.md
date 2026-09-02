---
name: omaxian
description: >
  REQUIRED for end-user customization of this Linux desktop, window manager, or system config.
  Use when editing ~/.config/i3/, ~/.config/omarchy/, ~/.config/picom.conf, ~/.config/dunst/,
  ~/.config/kitty/, or ~/.config/i3/dunstrc.
  Triggers: i3, Omaxian, omarchy-shell, bar, dock, Control Panel, Settings, keybindings,
  window rules, gaps, borders, monitors, xrandr, themes, background, night light (redshift),
  lock screen (i3lock), screenshots (maim), reminders, display config, dunst, picom, and
  user-facing omarchy-* commands. Excludes Omaxian source development in the git checkout.
---

# Omaxian Skill

Manage [Omaxian](https://github.com/aozora/omaxian) — Omarchy for Devuan / Debian + X11 + i3.
Same bar, themes, launcher, and `omarchy-*` commands; no Wayland, Hyprland, or systemd.

This skill is for end-user customization on an installed desktop.
It is not for contributing to the Omaxian source tree.

## When This Skill MUST Be Used

**ALWAYS invoke this skill for end-user requests involving ANY of these:**

- Editing ANY file in `~/.config/i3/` (keybindings, window rules, gaps, autostart, …)
- Editing `~/.config/omarchy/shell.json` (status bar layout, widgets, plugins)
- Editing `~/.config/omarchy/dock-settings.json` / `dock-pinned.json`
- Editing terminal configs (kitty; also alacritty/foot/ghostty if the user has them)
- Editing ANY file in `~/.config/omarchy/`
- Window behavior, gaps, borders, floating rules, workspace assignments
- Display/monitor configuration (xrandr / Control Panel Displays / Super+Ctrl+D)
- Themes, backgrounds, fonts, appearance
- User-facing `omarchy-*` commands (`omarchy-theme-set`, `omarchy-restart-shell`, …)
- Screenshots, reminders, night light (redshift), lock screen (i3lock)

**If you're about to edit a config file in ~/.config/ on this system, STOP and use this skill first.**

**Do NOT use this skill for Omaxian development tasks** (editing the git checkout under `omaxian/`, `setup.sh` / `install.sh` / `deploy.sh`, or Quickshell source). Follow the repository `AGENTS.md` instead.

## Topic Guides

Deeper instructions for common areas live next to this file. Read the
matching guide before starting:

- [`i3.md`](i3.md) - keybindings, monitors, window rules, and other i3 config
- [`plugins.md`](plugins.md) - the Omaxian shell: bar, dock, widgets, plugins, idle
- [`theming.md`](theming.md) - themes, backgrounds, and fonts
- [`capture.md`](capture.md) - screenshots and the color picker
- [`contributing.md`](contributing.md) - reporting Omaxian bugs vs upstream Omarchy

## Critical Safety Rules

For privileged commands, follow the Privilege Escalation rules below: `sudo` when a terminal is available for the password prompt, `pkexec` when it is not. Do not wrap commands that already manage privilege elevation themselves.

**For end-user customization tasks, NEVER modify anything in `~/.local/share/omarchy/` except by using the shipped commands** — but READING is safe and encouraged.

That directory is the installed port (`bin/`, `shell/`, stock `themes/`, `default/`). `./deploy.sh` / `./install.sh` overwrite it from the git checkout. User edits there are lost on the next deploy.

```
~/.local/share/omarchy/     # READ-ONLY for end-user customization (reading is OK)
├── bin/                    # omarchy-* commands (on PATH via ~/.xsessionrc)
├── shell/                  # Quickshell source
├── themes/                 # Stock themes (from install.sh)
└── default/                # Menu JSONC, themed templates, agent skills
```

There is no `/usr/share/omarchy/` in this port.

**Reading `~/.local/share/omarchy/` is SAFE and useful** — do it freely to:

- Understand how commands work: `cat "$(which omarchy-theme-set)"`
- See default configs before customizing
- Check stock theme files to copy for a user overlay
- Reference default i3 files: `ls ~/.config/i3/config.d/`

**Always use these safe locations instead:**

- `~/.config/` — user configuration (safe to edit)
- `~/.config/omarchy/themes/<custom-name>/` — custom themes
- `~/.config/omarchy/themed/` — template overrides
- `~/.config/omarchy/plugins/` — cloned / third-party shell plugins

If the request is to develop Omaxian itself, this skill is out of scope.

## Privilege Escalation

For an interactive script or command run in a visible terminal, use `sudo` for
privileged work. The terminal is the appropriate place to request a password
when one is needed.

Use `pkexec` only when the caller cannot interact with a terminal or cannot
enter a password there, such as a command launched by an agent or a graphical
background process. Do not replace `sudo` with `pkexec` merely because a
command changes system state. `mate-polkit` (or `xfce-polkit`) must be running
for graphical `pkexec` prompts.

This port does not ship passwordless sudoers rules under `/etc/sudoers.d/`.

## System Architecture

Omaxian is built on:

| Component | Purpose | Config location |
|-----------|---------|-----------------|
| **Devuan / Debian** | Base OS (elogind, not systemd) | `/etc/`, `~/.config/` |
| **i3** | X11 window manager | `~/.config/i3/` |
| **picom** | Compositor | `~/.config/i3/picom.conf` |
| **dunst** | Notifications | `~/.config/i3/dunstrc` |
| **Omaxian shell** | Status bar + panels (Quickshell) | `~/.config/omarchy/shell.json` |
| **Launcher / menus** | Quickshell menu | `$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc` |
| **kitty** | Terminal | `~/.config/i3/kitty/` or `~/.config/kitty/` |
| **Omaxian OSD** | On-screen display | Quickshell plugin |

`$OMARCHY_PATH` is `$HOME/.local/share/omarchy`.

## Command Discovery

There is **no** `omarchy` group dispatcher. Commands are `omarchy-*` binaries on `PATH` (prepended by `~/.xsessionrc`).

```bash
# List installed helpers
ls "$OMARCHY_PATH/bin"/omarchy-*

# Read a command's source
cat "$(which omarchy-theme-set)"

# Shell IPC (does not start the shell)
omarchy-shell shell ping
omarchy-shell shell listPlugins
omarchy-theme-set --help 2>/dev/null || omarchy-theme-set
```

### Common commands

| Command | Purpose |
|---------|---------|
| `omarchy-restart-shell` | Restart Quickshell |
| `omarchy-theme-list` / `omarchy-theme-set` / `omarchy-theme-next` | Themes |
| `omarchy-theme-bg-next` / `omarchy-theme-bg-set` | Wallpapers |
| `omarchy-toggle-nightlight` | Night light (redshift) |
| `omarchy-toggle-bar` | Show / hide the bar |
| `omarchy-plugin-list` / `clone` / `add` / `enable` / `disable` | Plugins |
| `omarchy-plugin-check` | Static X11/Debian check before installing a community plugin |
| `omarchy-reminder` | Desktop notification reminders |
| `omarchy-system-lock` / `logout` / `reboot` / `shutdown` | Session |
| `omarchy-notification-send` | Notifications (do not call `notify-send` from new scripts) |

There is no `omarchy pkg`, `omarchy update`, `omarchy refresh`, `omarchy debug`, or `omarchy capture`. Packages: `apt`. Config reset: copy from the git checkout with `./deploy.sh`, or restore a backup you made. Diagnostics: `~/.local/state/omarchy/shell.log`.

## Configuration Locations

i3 config lives in `~/.config/i3/` — see [`i3.md`](i3.md).
The shell (bar, dock, plugins) is configured in `~/.config/omarchy/shell.json`
and the Settings panel (Super+Ctrl+S) — see [`plugins.md`](plugins.md).

### Other configs

| App | Location |
|-----|----------|
| picom | `~/.config/i3/picom.conf` |
| dunst | `~/.config/i3/dunstrc` |
| kitty | `~/.config/i3/kitty/` |
| xsettingsd | `~/.config/i3/xsettingsd` |

## Safe Customization Patterns

### Edit user config directly

```bash
# 1. Read current config
cat ~/.config/i3/config.d/02_keybindings.conf

# 2. Backup before changes
cp ~/.config/i3/config.d/02_keybindings.conf ~/.config/i3/config.d/02_keybindings.conf.bak.$(date +%s)

# 3. Make changes with Edit tool

# 4. Apply
# - i3: i3-msg reload
# - Omarchy shell: shell.json hot-reloads; QML needs omarchy-restart-shell
# - Menus: the menu JSONC is under $OMARCHY_PATH/default/ — prefer a user
#   extension if one exists; otherwise document that deploy.sh will overwrite
```

### Reset to defaults — ALWAYS SEEK USER CONFIRMATION BEFORE RUNNING

There is no `omarchy refresh`. Re-copy from the Omaxian git checkout:

```bash
# From the clone the user installed from:
./deploy.sh
omarchy-restart-shell
```

That overwrites `~/.config/i3/` and the share tree from the repo. Confirm
first. For a single file, copy just that file from the checkout.

## System Commands

```bash
omarchy-system-lock       # i3lock / i3lock-fancy
omarchy-system-logout     # loginctl / i3-msg exit
omarchy-system-shutdown
omarchy-system-reboot
```

Idle auto-lock is **not ported**. Super+Ctrl+L locks. `idle.lock` in
`shell.json` does not start a locker.

## Troubleshooting

```bash
omarchy-shell shell ping
tail -n 80 ~/.local/state/omarchy/shell.log
omarchy-restart-shell
```

Empty bar usually means Quickshell started without `OMARCHY_PATH` — log out
and back in, or run `omarchy-restart-shell` from a terminal that has the
omarchy commands. Can't type in the menu: `sudo apt install python3-xlib`.

## Decision Framework

1. **Is it a stock omaxian command?** Use the `omarchy-*` binary directly
2. **Is it a config edit?** Edit in `~/.config/`, never `~/.local/share/omarchy/`
3. **Is it a theme customization?** Follow [`theming.md`](theming.md); create a NEW custom theme directory
4. **Is it a package install?** `sudo apt install …` (or ask the user to run `setup.sh`)
5. **Is it built-in shell/plugin code?** Follow [`plugins.md`](plugins.md); clone with `omarchy-plugin-clone`, never edit the share-tree copy
6. **Unsure if a command exists?** `ls "$OMARCHY_PATH/bin"/omarchy-*`

### Reminder requests

```bash
omarchy-reminder 15 "Pickup Jack"
omarchy-reminder 60 "Check laundry"
omarchy-reminder show
omarchy-reminder clear
```

Convert natural language durations to minutes.

## Out of Scope

Do not use this skill for:

- Editing files in the Omaxian git checkout (`omaxian/`, `setup.sh`, …)
- Editing `~/.local/share/omarchy/shell/` or `bin/` in place
- Running `omarchy dev …` (not shipped)
- Hyprland / `hyprctl` / `uwsm` / pacman workflows from upstream Omarchy docs

## Example Requests

- "Change my theme to Tokyo Night" → `omarchy-theme-set "Tokyo Night"`
- "Add a keybinding for Super+E to open the file manager" → edit `~/.config/i3/config.d/02_keybindings.conf`, then `i3-msg reload`
- "Configure my external monitor" → Super+Ctrl+D / `omarchy-shell shell toggle omaxian.monitor`, or `omarchy-monitor-set`
- "Make the window gaps smaller" → edit `~/.config/i3/config.d/01_theme.conf` (`$i3_gaps_inner`)
- "Turn on night light" → `omarchy-toggle-nightlight`
- "Set a reminder to pickup jack in 15 minutes" → `omarchy-reminder 15 "Pickup Jack"`
- "Customize a theme's colors" → overlay in `~/.config/omarchy/themes/<slug>/` (see `theming.md`)
- "Change how workspace labels are rendered" → `omarchy-plugin-clone omarchy.workspaces`, then edit the clone
- "Reset the bar" → Settings (Super+Ctrl+S) or restore `~/.config/omarchy/shell.json` from the checkout
- "Take a screenshot" → Super+Ctrl+C or `i3_screenshot --now` (see `capture.md`)
- "Report this bug" → see `contributing.md`
