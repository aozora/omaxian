# Omaxian

Omaxian is [Omarchy](https://omarchy.org) for **Devuan / Debian + X11/XLibre + i3**.
Same bar, themes, launcher, and `omarchy-*` commands — no Wayland, Hyprland, or systemd.

This checkout has two trees:

- `omarchy-quattro/` — pinned clone of upstream Omarchy. Treat it as **read-only**. Do not edit it. `setup.sh` / `install.sh` clone it; it is gitignored.
- `omaxian/` — the port. Edit here. `./deploy.sh` copies it into `$HOME`.

See `README.md` for install, keybinds, and the list of things that are not 1:1 with Omarchy. Porting notes live in `docs/omarchy-port/`.

**Recommended packages:** `upower`, `light`, `pactl` (pulseaudio-utils or pipewire-pulse), `playerctl`, `bluez`, `python3-gi` + NetworkManager, `papirus-icon-theme`, `fonts-jetbrains-mono`, `maim`, `xclip`, `dunst`, `gpick` (color picker; replaces Arch `xcolor`), `i3lock-fancy` (uses `i3lock` + `maim`), `xss-lock` (optional, registers locker for loginctl), `mate-polkit` or `xfce-polkit`.

# Task Guides

Deeper instructions for specific kinds of work live in `agents/skills/`. Read the
matching guide before starting:

- [`agents/skills/command-metadata.md`](agents/skills/command-metadata.md) - adding or changing commands in `omaxian/.local/share/omarchy/bin/`
- [`agents/skills/install-scripts.md`](agents/skills/install-scripts.md) - working on `setup.sh`, `install.sh`, or `deploy.sh`
- [`agents/skills/shell-dev.md`](agents/skills/shell-dev.md) - editing the Quickshell desktop under `omaxian/.local/share/omarchy/shell/`
- [`agents/skills/icon-font.md`](agents/skills/icon-font.md) - glyphs in the bar and menu (Omaxian does not ship Omarchy's branded TTF)
- [`agents/skills/acceptance-tests.md`](agents/skills/acceptance-tests.md) - this port has no ISO/VM acceptance suite; how to smoke-check instead
- [`agents/skills/visual-verification.md`](agents/skills/visual-verification.md) - verifying any change with a visual effect in the running UI

End-user customization on an installed desktop (not this source tree) follows
[`omaxian/.local/share/omarchy/default/agents/skills/omaxian/SKILL.md`](omaxian/.local/share/omarchy/default/agents/skills/omaxian/SKILL.md).

# Style

- Two spaces for indentation in `omarchy-*` commands and new QML; no tabs there
- `setup.sh`, `install.sh`, and `deploy.sh` already use tabs — match the file you are in
- Use bash 5 conditionals: use `[[ ]]` for string/file tests and `(( ))` for numeric tests
- In `[[ ]]`, don't quote variables, but do quote string literals when comparing values (e.g., `[[ $branch == "dev" ]]`)
- Prefer `(( ))` over numeric operators inside `[[ ]]` (e.g., `(( count < 50 ))`, not `[[ $count -lt 50 ]]`)
- For strings/paths with spaces, quote them instead of escaping spaces with `\ ` (e.g., `"$APP_DIR/Disk Usage.desktop"`, not `$APP_DIR/Disk\ Usage.desktop`)
- Shebangs on `omarchy-*` commands must use `#!/bin/bash` (never `#!/usr/bin/env bash`)
- Archcraft-derived i3 scripts under `omaxian/.config/i3/scripts/` may keep `#!/usr/bin/env bash`; do not churn them just to change the shebang

# Command Naming

User-facing commands are still named `omarchy-*` (upstream compatibility). There is **no** `omarchy` group dispatcher in this port — invoke the binaries directly (`omarchy-theme-set`, not `omarchy theme set`).

Prefixes indicate purpose. Common ones:

- `cmd-` - check if commands exist
- `pkg-` - not ported; use `apt` / `setup.sh`
- `hw-` - hardware detection (return exit codes for use in conditionals)
- `refresh-` - not ported; change the file in `omaxian/` and `./deploy.sh`
- `restart-` - restart a component
- `launch-` - open applications
- `setup-` - not a packaged group here; system setup is `setup.sh`
- `toggle-` - toggle features on/off
- `theme-` - theme management
- `plugin-` - shell plugins (`omarchy-plugin-check` is Omaxian-only)

Keep `# omarchy:group=` / `# omarchy:summary=` metadata on new commands consistent with existing files in `omaxian/.local/share/omarchy/bin/`. See [`agents/skills/command-metadata.md`](agents/skills/command-metadata.md).

# Runtime Environment

- `$OMARCHY_PATH` is `$HOME/.local/share/omarchy`. `~/.xsessionrc` (installed by `deploy.sh`) exports it and prepends `$OMARCHY_PATH/bin` to `PATH` before i3 starts. LightDM must run `/etc/X11/Xsession` for that to take effect.
- There is no `uwsm`. Commands and QML may use `${OMARCHY_PATH:=$HOME/.local/share/omarchy}` when the session env might be missing (terminals started outside the X session, `i3 restart` without a re-login).
- Quickshell QML should read `Quickshell.env("OMARCHY_PATH")` when the host has already exported it; `omarchy-launch-shell` / `omarchy-restart-shell` set it before starting the process.
- After the first deploy, **log out and back in** (not `i3 restart`) so i3 inherits `PATH`. Afterwards, QML edits need `omarchy-restart-shell`.

# Privileged Commands

- Follow the "Privilege Escalation" section of
  [`omaxian/.local/share/omarchy/default/agents/skills/omaxian/SKILL.md`](omaxian/.local/share/omarchy/default/agents/skills/omaxian/SKILL.md).
  It draws the `sudo`/`pkexec` line by whether the caller has a terminal to enter a password in. `omarchy-dns` is the in-tree example.

# Git

- Commits should be atomic: include only one coherent change or fix, and do not mix unrelated work.
- Commit messages should be succinct and describe the change being made.
- Do not commit `omarchy-quattro/` (gitignored). Do not vendor upstream.

# Helper Commands

Use these instead of raw shell commands where they exist:

- `omarchy-cmd-present` - check that all named commands are on `PATH`
- `omarchy-notification-send` - send desktop notifications; do not call `notify-send` / `dunstify` directly from new `omarchy-*` code
- `omarchy-restart-shell` - restart Quickshell after QML / theme-file edits
- `omarchy-plugin-check` - static X11/Debian compatibility check for a community plugin
- `omarchy-session-is-i3` - exit 0 only in a live i3 session

There is no `omarchy-pkg-add` / `omarchy-pkg-drop`. Install packages with `apt` (via `setup.sh` for the default sets). Do not add `pacman` or AUR paths.

Commands that `setup.sh` installs as required are runtime invariants on a deployed desktop. Invoke them directly; do not add defensive `omarchy-cmd-present` checks around `i3`, `dunst`, `kitty`, and the like. Use command-presence helpers only for optional dependencies (`redshift`, `xkb-switch`, `i3lock-fancy`, GPU tools).

# Menu

- The menu definition lives in `omaxian/.local/share/omarchy/default/omarchy/omarchy-menu.jsonc` (overlaid onto `$OMARCHY_PATH/default/omarchy/` at install).
- Do not add Arch Install/Remove trees, AUR, or Hyprland-only actions.
- Do not add `aliases` to new menu entries. Aliases are reserved for established alternate names users already type.

# Config Structure

| Tree | Role |
|------|------|
| `omaxian/.config/` | Default user configs deployed to `~/.config/` (i3, omarchy, picom, dunst, …) |
| `omaxian/.local/share/omarchy/bin/` | Ported `omarchy-*` commands |
| `omaxian/.local/share/omarchy/shell/` | Quickshell desktop |
| `omaxian/.local/share/omarchy/default/` | Port overlays (menu JSONC, agent skills) on top of upstream `default/` |
| `~/.local/share/omarchy/themes/` | Stock themes, seeded from upstream by `install.sh` |
| `~/.config/omarchy/themes/` | User theme overlays only |
| `~/.config/omarchy/themed/*.tpl` | User template overrides (`{{ variable }}` placeholders) |
| `~/.local/state/omarchy/current/theme/` | Active theme (written by `omarchy-theme-set`) |

# Tests

This port has no `./test/all`, CLI harness, or graphical acceptance VM. After a change:

- Run `omarchy-shell shell ping` (expect `ok`) and `omarchy-shell shell listPlugins` if the shell is involved
- For a community plugin, run `omarchy-plugin-check <dir-or-url>`
- Visual changes must be verified in the running UI; follow [`agents/skills/visual-verification.md`](agents/skills/visual-verification.md)

Do not call `omarchy-iso` workflows — they are Arch/Hyprland ISO tests and do not apply here.

# Deploy Pattern

Edit files under `omaxian/`, then:

```bash
./deploy.sh
omarchy-restart-shell   # after QML, shell.json that failed to hot-reload, or theme templates
```

`deploy.sh` overwrites configs from this repo but does not delete files an older deploy left behind. `install.sh` refreshes themes, upstream `default/`, and `bin/` into `~/.local/share/omarchy/`.

i3 config lives in `omaxian/.config/i3/` (`config` plus `config.d/*.conf`). After deploying i3 files, `i3-msg reload` is enough for binds and rules; a full logout is required when `PATH` / `OMARCHY_PATH` changed.
