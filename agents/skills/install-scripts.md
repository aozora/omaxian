# Install Scripts

Read this before working on `setup.sh`, `install.sh`, `deploy.sh`, or the
session/user setup they perform.

Omaxian has no ISO and no `install/` leaf tree. Three root scripts own setup:

- `setup.sh` (root via sudo) — apt packages, fonts, session D-Bus
  (`use-session-dbus` in `/etc/X11/Xsession.options`), and a pinned clone of
  upstream into `omarchy-quattro/`. Flags: `--minimal`, `--optional`, `--deploy`.
- `install.sh` (login user) — seed `~/.local/share/omarchy/{themes,default,bin}`
  and `~/.config/omarchy/{themes,themed}`. Themes and `default/` come from
  `omarchy-quattro/`; `bin/` and the menu/agents overlays come from `omaxian/`.
- `deploy.sh` (login user) — copy `omaxian/.config/*`, `omaxian/.local/share/*`,
  `omaxian/.xsessionrc`, and `omaxian/.icons` into `$HOME`. Seeds
  `~/.config/omarchy/shell.json` from `$OMARCHY_PATH/shell.json` only when
  the user file is missing (Settings / bar layout survive redeploy).

Keep these rules:

- `setup.sh` is the only script that should call `apt-get`. Package sets live
  in `REQUIRED`, `RECOMMENDED`, and `OPTIONAL` arrays there.
- `install.sh` and `deploy.sh` must refuse to run as root (re-exec as
  `$SUDO_USER` / exit). Never seed `/root`.
- Use `$OMARCHY_PATH` / `$HOME/.local/share/omarchy` instead of hard-coded
  machine-specific paths. `~/.xsessionrc` is what exports `OMARCHY_PATH` for i3.
- `omarchy-quattro/` is cloned, not vendored. Do not copy upstream into git.
  Bump `OMARCHY_UPSTREAM_REF` when moving to a newer tag.
- After copying upstream `default/`, overlay the port's
  `omarchy-menu.jsonc` and `default/agents/` so Arch/Hyprland menu entries and
  agent skills do not ship to users.
- `~/.config/omarchy/themes` is for user overlays — `install.sh` must not fill
  it with stock themes.
- Prefer `omarchy-cmd-present` for optional tools. Raw `command -v` and `apt`
  are fine in `setup.sh`, where talking to the package manager is the point.
- Do not add `pacman`, AUR, `uwsm`, or systemd unit installers.

Idempotence: `setup.sh` and `deploy.sh` are safe to re-run. `install.sh`
replaces `themes/`, `default/`, and `bin/` under the share dir on every run;
dock settings and `~/.config/omarchy/shell.json` are written only when missing.
