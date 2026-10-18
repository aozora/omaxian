# Install Scripts

Read this before working on `scripts/setup.sh`, `scripts/install.sh`,
`scripts/deploy.sh`, `omaxian-install.sh`, `bootstrap.sh`,
`scripts/install-community-plugins.sh`, or the session/user setup they perform.

User-facing reference (roles, flags, re-run guide, why they stay separate):
[`docs/omaxian/install-scripts.md`](../../docs/omaxian/install-scripts.md).
Community plugins: [`community-plugins/README.md`](../../community-plugins/README.md).

Omaxian has no ISO and no `install/` leaf tree. Layout:

- `omaxian-install.sh` — whiptail TUI one-shot (login user; sudo for apt).
- `bootstrap.sh` — `curl | bash` clone + hand-off to `omaxian-install.sh`.
- Root `setup.sh` / `install.sh` / `deploy.sh` — thin shims → `scripts/*`.
- `scripts/setup.sh` (root via sudo) — apt packages, fonts, session D-Bus
  (`use-session-dbus` in `/etc/X11/Xsession.options`), and a pinned clone of
  upstream into `omarchy-quattro/`. Flags: `--minimal`, `--optional`, `--deploy`.
- `scripts/install.sh` (login user) — seed `~/.local/share/omarchy/{themes,default,bin}`
  and `~/.config/omarchy/{themes,themed}`. Themes and `default/` come from
  `omarchy-quattro/`; Omaxian-only themes under
  `omaxian/.local/share/omarchy/themes/` are overlaid afterward (default:
  `nebula-ridge`). `bin/` and the menu/agents overlays come from `omaxian/`.
- `scripts/deploy.sh` (login user) — copy `omaxian/.config/*`, `omaxian/.local/share/*`,
  `omaxian/.xsessionrc`, and `omaxian/.icons` into `$HOME`. Seeds
  `~/.config/omarchy/shell.json` from `$OMARCHY_PATH/shell.json` only when
  the user file is missing (Settings / bar layout survive redeploy).
- `scripts/install-community-plugins.sh` — opt-in local ports + `omaxian.deps.json`
  apt installs. Not called by setup/install/deploy.

Keep these rules:

- `scripts/setup.sh` owns the **desktop** package sets (`REQUIRED` /
  `RECOMMENDED` / `OPTIONAL`). Community-plugin apt packages live only in each
  port’s `omaxian.deps.json` and are installed by
  `scripts/install-community-plugins.sh` (or the TUI). The only other
  intentional apt callers are the tiny preflight installs in
  `omaxian-install.sh` (`whiptail`) and `bootstrap.sh` (`git`).
- `install.sh` and `deploy.sh` must refuse to run as root (re-exec as
  `$SUDO_USER` / exit). Never seed `/root`. Same for the TUI / plugin helper.
- Use `$OMARCHY_PATH` / `$HOME/.local/share/omarchy` instead of hard-coded
  machine-specific paths. `~/.xsessionrc` is what exports `OMARCHY_PATH` for i3.
- Scripts under `scripts/` set `REPO_DIR` to the **parent** of `scripts/` (repo
  root), not to `scripts/` itself.
- `omarchy-quattro/` is cloned, not vendored. Do not copy upstream into git.
  Bump `OMARCHY_UPSTREAM_REF` when moving to a newer tag (in both setup and
  install).
- After copying upstream `default/`, overlay the port's
  `omarchy-menu.jsonc` and `default/agents/` so Arch/Hyprland menu entries and
  agent skills do not ship to users.
- `~/.config/omarchy/themes` is for user overlays — `install.sh` must not fill
  it with stock themes.
- Prefer `omarchy-cmd-present` for optional tools. Raw `command -v` and `apt`
  are fine in `setup.sh` / the community helper, where talking to the package
  manager is the point.
- Do not add `pacman`, AUR, `uwsm`, or systemd unit installers.

Idempotence: `setup.sh` and `deploy.sh` are safe to re-run **while logged
into i3**. `deploy.sh` copies with `rsync` (temp file + rename) so it does
not truncate long-running session scripts (`i3_display_watch.sh`,
`omarchy-launch-shell`). A naive `cp -r` can make those scripts execute
garbage (including `xrandr --off`) and look like a full desktop crash.

On a live session `deploy.sh` also: writes `$XDG_RUNTIME_DIR/omaxian-deploy.lock`
(Quickshell ignores FileView / plugin reloads), **stops picom** for the
copy, then restarts picom. It never runs `i3-msg reload` or
`omarchy-restart-shell`. QML applies on the next login.

**Agent hard rule:** do not run `omarchy-restart-shell`, and do not stop
picom / kill Quickshell outside of `deploy.sh`'s own live-session path.
Overlapping restarts have crashed the X session. Prefer telling the user to
log out after deploy.

`omarchy-restart-shell` stops picom before tearing down Quickshell (glx +
ARGB window destroy freezes X), then starts picom again. Still prefer
logout for QML after a deploy.

Session startup (`omarchy-monitor-apply`, `i3_autostart`, `i3_alternating_layout`) is
`exec` (login) so `i3-msg reload` is config-only.

`install.sh` replaces `themes/`, `default/`, and `bin/` under the share dir
on every run; dock settings and `~/.config/omarchy/shell.json` are written
only when missing.
