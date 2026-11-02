# Install scripts

Day-one install is **[`omaxian-install.sh`](../../omaxian-install.sh)** (TUI) or
**[`bootstrap.sh`](../../bootstrap.sh)** (`curl | bash`). The three privilege-split
scripts live under [`scripts/`](../../scripts/); root `setup.sh` / `install.sh` /
`deploy.sh` are thin shims.

Agent-oriented rules:
[`agents/skills/install-scripts.md`](../../agents/skills/install-scripts.md).
Upstream clone / pin bumps:
[`docs/omarchy-port/upstream-tracking.md`](../omarchy-port/upstream-tracking.md).

---

## At a glance

| Script | Who runs it | Privilege | What it does |
| --- | --- | --- | --- |
| [`omaxian-install.sh`](../../omaxian-install.sh) | first-time / guided | **user** (sudo for apt) | whiptail TUI: setup → install → deploy → optional community plugins |
| [`bootstrap.sh`](../../bootstrap.sh) | first-time remote | **user** | clone repo (or reuse), then `exec` `omaxian-install.sh` |
| [`scripts/setup.sh`](../../scripts/setup.sh) | once per machine (or when deps change) | **root** (`sudo`) | `apt` packages, session D-Bus, root-owned `omarchy-dns`, bundled fonts; may clone `omarchy-quattro/` |
| [`scripts/install.sh`](../../scripts/install.sh) | login user | **user** (refuses root) | seed `~/.local/share/omarchy/{themes,default,bin}` from upstream + the port |
| [`scripts/deploy.sh`](../../scripts/deploy.sh) | login user | **user** (refuses root) | copy `omaxian/` into `$HOME` (i3, Quickshell, `.xsessionrc`, …) |
| [`scripts/install-community-plugins.sh`](../../scripts/install-community-plugins.sh) | opt-in | **user** (+ sudo for plugin apt) | copy selected `community-plugins/` ports; install `omaxian.deps.json` apt packages |

```text
  omaxian-install.sh / bootstrap.sh
       └─► scripts/setup.sh     → system packages + /etc + /usr/local/libexec
       └─► scripts/install.sh   → ~/.local/share/omarchy  (themes / default / bin)
       └─► scripts/deploy.sh    → ~/.config, ~/.local/share (shell, …), ~/.xsessionrc
       └─► (optional) install-community-plugins.sh
```

Desktop `setup` / `install` / `deploy` never copy community plugins. The TUI
(or the helper above) does that only when you opt in.

---

## Why keep setup / install / deploy separate

1. **Privilege boundary** — `setup.sh` must use `apt` and write under `/etc` and
   `/usr/local`. `install.sh` / `deploy.sh` must never seed `/root` or run as
   root. A single blob still needs the same split internally.
2. **Re-run cadence** — after `git pull` you usually want `./scripts/install.sh`
   and/or `./scripts/deploy.sh`, not another `apt-get`.
3. **Partial / multi-user setups** — an admin can run `sudo ./scripts/setup.sh`
   once; each login user runs install + deploy.
4. **Safety on a live i3 session** — `deploy.sh` pauses picom and freezes shell
   file-reload; it must not be mixed with privileged package install paths.

They are **not** candidates for a full merge. Convenience wrappers:
`omaxian-install.sh`, `bootstrap.sh`, and `scripts/setup.sh --deploy`.

---

## First-time install

```sh
curl -fsSL https://raw.githubusercontent.com/aozora/omaxian/main/bootstrap.sh | bash
```

Or from a clone:

```sh
./omaxian-install.sh
# noninteractive: ./omaxian-install.sh --yes
```

Advanced (no TUI):

```sh
sudo ./scripts/setup.sh
./scripts/install.sh && ./scripts/deploy.sh
# or: sudo ./scripts/setup.sh --deploy
```

**Then log out and back in** (not `i3 restart`) so i3 inherits `PATH` /
`OMARCHY_PATH` from `~/.xsessionrc`.

Smoke:

```sh
omarchy-shell shell ping                 # → ok
omarchy-shell shell listPlugins | jq length
pgrep -x quickshell
```

---

## `omaxian-install.sh` (TUI)

- Ensures `whiptail` + `dialog` (apt-installs them if missing).
- Asks for the sudo password in a whiptail password box (cached for apt).
- Streams setup/apt/install/deploy output through `dialog --programbox` so the
  flow stays in the TUI instead of dropping to a bare terminal.
- Quiet steps (notably `apt-get update -qq` in `setup.sh`) use `omaxian_spin`
  from `scripts/lib/ui.sh` — a TTY spinner, or heartbeat lines inside the
  programbox — so the install does not look frozen.
- Package radiolist: recommended (default) / minimal / + optional.
- Runs `scripts/setup.sh` (no `--deploy`), then `install.sh`, then `deploy.sh`.
- Checks that **Quickshell** is on `PATH` after setup. If missing, shows
  README-aligned install instructions (apt, Debian Forky / Devuan Freia pinning,
  or build-from-source) and flags the final checklist; does not abort the rest
  of the install.
- Asks whether to install community plugins; if yes, checklist + deps confirm
  (union of each port’s `omaxian.deps.json` `apt` list), then
  `scripts/install-community-plugins.sh`.
- `--yes` / `OMAXIAN_INSTALL_NONINTERACTIVE=1`: recommended desktop only, skip plugins
  (still prints the Quickshell warning when missing).

Bootstrap env: `OMAXIAN_DIR` (default `~/projects/omaxian`), `OMAXIAN_REF`,
`OMAXIAN_REPO`.

---

## `setup.sh` (system)

```sh
sudo ./scripts/setup.sh              # required + recommended
sudo ./scripts/setup.sh --minimal    # required only
sudo ./scripts/setup.sh --optional   # also VM / GPU / niche extras
sudo ./scripts/setup.sh --deploy     # then run install.sh + deploy.sh as you
```

| Concern | Detail |
| --- | --- |
| Privilege | Re-execs under `sudo` if needed. Desktop package installs live here. |
| Upstream | Clones `omarchy-quattro/` when missing (same pin as `install.sh`). |
| Packages | Arrays `REQUIRED`, `RECOMMENDED`, `OPTIONAL` in the script. Skips names this suite does not ship; warns (e.g. `quickshell` on Debian &lt; 13 / Devuan). |
| Session | Enables `use-session-dbus` in `/etc/X11/Xsession.options` so Quickshell reaches the bus. |
| Privileged helper | Installs root-owned `/usr/local/libexec/omaxian/omarchy-dns`. |
| Fonts | Copies bundled fonts into the target user’s `~/.local/share/fonts` and runs `fc-cache`. |
| Idempotent | Safe to re-run. |

On non-systemd hosts it may pull **elogind** so `loginctl` / `xss-lock` work.

Community-plugin apt packages are **not** in these arrays — see each port’s
`omaxian.deps.json` and `install-community-plugins.sh`.

---

## `install.sh` (share tree)

```sh
./scripts/install.sh
OMARCHY_UPSTREAM_URL=… OMARCHY_UPSTREAM_REF=… ./scripts/install.sh
```

| Concern | Detail |
| --- | --- |
| Privilege | Must be the login user. If invoked via `sudo`, re-execs as `$SUDO_USER`. |
| Upstream | Clones `omarchy-quattro/` when missing; leaves an existing checkout alone. |
| Writes | Always replaces `~/.local/share/omarchy/{themes,default,bin}`. Themes + `default/` from upstream; Omaxian-only themes (e.g. `nebula-ridge`) overlaid from `omaxian/`; `bin/` and menu/agents overlays from the port. |
| Leaves alone | `~/.config/omarchy/themes` (user overlays only — left empty on purpose). Dock settings file written only when missing. |
| Does not | Deploy i3 / Quickshell / `.xsessionrc` — that is `deploy.sh`. |

Bump upstream: wipe the clone, set the pin in **both** `scripts/setup.sh` and
`scripts/install.sh` (or pass `OMARCHY_UPSTREAM_REF`), then re-run `install.sh`. See
[upstream-tracking](../omarchy-port/upstream-tracking.md).

---

## `deploy.sh` (home configs)

```sh
./scripts/deploy.sh
```

| Concern | Detail |
| --- | --- |
| Privilege | Login user only; refuses root. |
| Copies | `omaxian/.config/*` → `~/.config/`; `omaxian/.local/share/*` → `~/.local/share/`; `omaxian/.xsessionrc`; `omaxian/.icons`. |
| `shell.json` | Seeds `~/.config/omarchy/shell.json` from `$OMARCHY_PATH/shell.json` **only when missing**. Settings / bar layout survive redeploy. Never delete that user file from automation. |
| `keyboard.json` | Seeds `~/.config/omarchy/keyboard.json` from `/etc/default/keyboard` **only when missing** (`omarchy-keyboard-apply --seed-config`). Never overwrite an existing user layout list. |
| Live i3 | Raises `$XDG_RUNTIME_DIR/omaxian-deploy.lock`, **stops picom** for the copy, rsyncs (temp + rename — no truncate of open scripts), restarts picom. Does **not** run `i3-msg reload` or `omarchy-restart-shell`. |
| QML | Applies on the **next full login**. Optional after deploy returns: `i3-msg reload` for binds only. |

`deploy.sh` overwrites files that exist in the port tree; it does not delete
orphans left from older deploys.

---

## What to re-run when

| Situation | Command |
| --- | --- |
| Fresh machine | `./omaxian-install.sh` or `curl …/bootstrap.sh \| bash` |
| Fresh machine (no TUI) | `sudo ./scripts/setup.sh` then `./scripts/install.sh && ./scripts/deploy.sh` (or `--deploy`) |
| New apt deps / fonts / `omarchy-dns` | `sudo ./scripts/setup.sh` |
| New upstream tag / themes / `bin/` | wipe `omarchy-quattro/` if bumping pin → `./scripts/install.sh` (often deploy too) |
| QML, i3, picom, dunst, or other `omaxian/` edits | `./scripts/deploy.sh`, then **log out / log in** for QML |
| Only i3 binds changed (already deployed) | `i3-msg reload` after deploy returns |
| Optional community plugin | TUI, or `./scripts/install-community-plugins.sh` — see [`community-plugins/README.md`](../../community-plugins/README.md) |

---

## Paths cheat sheet

| Path | Role | Written by |
| --- | --- | --- |
| `omarchy-quattro/` | Pinned upstream clone (gitignored, read-only) | `setup.sh` / `install.sh` when absent |
| `~/.local/share/omarchy/` (`$OMARCHY_PATH`) | Stock themes, `default/`, `bin/`, shell after deploy | `install.sh` + `deploy.sh` |
| `~/.config/omarchy/shell.json` | User bar / Settings layout | `deploy.sh` once if missing |
| `~/.config/omarchy/keyboard.json` | XKB layouts (Settings → Keyboard) | `deploy.sh` once from `/etc/default/keyboard` if missing |
| `~/.config/omarchy/themes/` | User theme overlays | user (install leaves empty) |
| `~/.config/omarchy/plugins/` | Community / third-party plugins | TUI helper, `omarchy-plugin-add`, or rsync |
| `community-plugins/*/omaxian.deps.json` | Declared apt + manual deps for a port | maintainers |
| `~/.xsessionrc` | Exports `OMARCHY_PATH` and prepends `bin` to `PATH` | `deploy.sh` |
