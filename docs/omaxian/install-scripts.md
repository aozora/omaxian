# `setup.sh`, `install.sh`, and `deploy.sh`

Three root scripts install and refresh Omaxian. They are separate on purpose:
different privilege, different targets, and different re-run habits. Day-one
install can still be one command via `setup.sh --deploy`.

Agent-oriented rules for editing these scripts live in
[`agents/skills/install-scripts.md`](../../agents/skills/install-scripts.md).
Upstream clone / pin bumps are covered in
[`docs/omarchy-port/upstream-tracking.md`](../omarchy-port/upstream-tracking.md).

---

## At a glance

| Script | Who runs it | Privilege | What it does |
| --- | --- | --- | --- |
| [`setup.sh`](../../setup.sh) | once per machine (or when deps change) | **root** (`sudo`) | `apt` packages, session D-Bus, root-owned `omarchy-dns`, bundled fonts; may clone `omarchy-quattro/` |
| [`install.sh`](../../install.sh) | login user | **user** (refuses root) | seed `~/.local/share/omarchy/{themes,default,bin}` from upstream + the port; may clone `omarchy-quattro/` |
| [`deploy.sh`](../../deploy.sh) | login user | **user** (refuses root) | copy `omaxian/` into `$HOME` (i3, Quickshell, `.xsessionrc`, …) |

```text
  setup.sh          → system packages + /etc + /usr/local/libexec
  install.sh        → ~/.local/share/omarchy  (themes / default / bin)
  deploy.sh         → ~/.config, ~/.local/share (shell, …), ~/.xsessionrc
```

**Not installed by any of these:** optional third-party ports under
[`community-plugins/`](../../community-plugins/README.md). Those stay opt-in at
`~/.config/omarchy/plugins/`.

---

## Why keep them separate

1. **Privilege boundary** — `setup.sh` must use `apt` and write under `/etc` and
   `/usr/local`. `install.sh` / `deploy.sh` must never seed `/root` or run as
   root. A single blob still needs the same split internally.
2. **Re-run cadence** — after `git pull` you usually want `./install.sh` and/or
   `./deploy.sh`, not another `apt-get`. Developers on a working desktop almost
   never need `setup.sh`.
3. **Partial / multi-user setups** — an admin can run `sudo ./setup.sh` once;
   each login user runs `./install.sh && ./deploy.sh`. Or you refresh themes and
   `bin/` without touching packages.
4. **Safety on a live i3 session** — `deploy.sh` pauses picom and freezes shell
   file-reload; it must not be mixed with privileged package install paths.

They are **not** candidates for a full merge. Optional convenience: one wrapper
that only calls the three in order (already available as `--deploy` on setup).

---

## First-time install

From the repo root, with an X11 login path that runs `/etc/X11/Xsession`:

```sh
sudo ./setup.sh          # packages, fonts, session D-Bus
./install.sh             # themes + omarchy-* commands
./deploy.sh              # i3 / Quickshell / ~/.xsessionrc
```

Or in one shot after packages:

```sh
sudo ./setup.sh --deploy   # setup, then install.sh + deploy.sh as $SUDO_USER
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

## `setup.sh` (system)

```sh
sudo ./setup.sh              # required + recommended
sudo ./setup.sh --minimal    # required only
sudo ./setup.sh --optional   # also VM / GPU / niche extras
sudo ./setup.sh --deploy     # then run install.sh + deploy.sh as you
```

| Concern | Detail |
| --- | --- |
| Privilege | Re-execs under `sudo` if needed. Only script that may call `apt-get`. |
| Upstream | Clones `omarchy-quattro/` when missing (same pin as `install.sh`). |
| Packages | Arrays `REQUIRED`, `RECOMMENDED`, `OPTIONAL` in the script. Skips names this suite does not ship; warns (e.g. `quickshell` on Debian &lt; 13 / Devuan). |
| Session | Enables `use-session-dbus` in `/etc/X11/Xsession.options` so Quickshell reaches the bus. |
| Privileged helper | Installs root-owned `/usr/local/libexec/omaxian/omarchy-dns` (do not elevate the copy under `~/.local/share/omarchy/bin`). |
| Fonts | Copies bundled fonts into the target user’s `~/.local/share/fonts` and runs `fc-cache`. |
| Idempotent | Safe to re-run. |

On non-systemd hosts it may pull **elogind** so `loginctl` / `xss-lock` work.

---

## `install.sh` (share tree)

```sh
./install.sh
OMARCHY_UPSTREAM_URL=… OMARCHY_UPSTREAM_REF=… ./install.sh
```

| Concern | Detail |
| --- | --- |
| Privilege | Must be the login user. If invoked via `sudo`, re-execs as `$SUDO_USER`. |
| Upstream | Clones `omarchy-quattro/` when missing; leaves an existing checkout alone. |
| Writes | Always replaces `~/.local/share/omarchy/{themes,default,bin}`. Themes + `default/` from upstream; Omaxian-only themes (e.g. `nebula-ridge`) overlaid from `omaxian/`; `bin/` and menu/agents overlays from the port. |
| Leaves alone | `~/.config/omarchy/themes` (user overlays only — left empty on purpose). Dock settings file written only when missing. |
| Does not | Deploy i3 / Quickshell / `.xsessionrc` — that is `deploy.sh`. |

Bump upstream: wipe the clone, set the pin in **both** `setup.sh` and
`install.sh` (or pass `OMARCHY_UPSTREAM_REF`), then re-run `install.sh`. See
[upstream-tracking](../omarchy-port/upstream-tracking.md).

---

## `deploy.sh` (home configs)

```sh
./deploy.sh
```

| Concern | Detail |
| --- | --- |
| Privilege | Login user only; refuses root. |
| Copies | `omaxian/.config/*` → `~/.config/`; `omaxian/.local/share/*` → `~/.local/share/`; `omaxian/.xsessionrc`; `omaxian/.icons`. |
| `shell.json` | Seeds `~/.config/omarchy/shell.json` from `$OMARCHY_PATH/shell.json` **only when missing**. Settings / bar layout survive redeploy. Never delete that user file from automation. |
| Live i3 | Raises `$XDG_RUNTIME_DIR/omaxian-deploy.lock`, **stops picom** for the copy, rsyncs (temp + rename — no truncate of open scripts), restarts picom. Does **not** run `i3-msg reload` or `omarchy-restart-shell`. |
| QML | Applies on the **next full login**. Optional after deploy returns: `i3-msg reload` for binds only. |

`deploy.sh` overwrites files that exist in the port tree; it does not delete
orphans left from older deploys.

---

## What to re-run when

| Situation | Command |
| --- | --- |
| Fresh machine | `sudo ./setup.sh` then `./install.sh && ./deploy.sh` (or `sudo ./setup.sh --deploy`) |
| New apt deps / fonts / `omarchy-dns` | `sudo ./setup.sh` |
| New upstream tag / themes / `bin/` | wipe `omarchy-quattro/` if bumping pin → `./install.sh` (often `./deploy.sh` too) |
| QML, i3, picom, dunst, or other `omaxian/` edits | `./deploy.sh`, then **log out / log in** for QML |
| Only i3 binds changed (already deployed) | `i3-msg reload` after deploy returns |
| Optional community plugin | **not** these scripts — see [`community-plugins/README.md`](../../community-plugins/README.md) |

---

## Paths cheat sheet

| Path | Role | Written by |
| --- | --- | --- |
| `omarchy-quattro/` | Pinned upstream clone (gitignored, read-only) | `setup.sh` / `install.sh` when absent |
| `~/.local/share/omarchy/` (`$OMARCHY_PATH`) | Stock themes, `default/`, `bin/`, shell after deploy | `install.sh` + `deploy.sh` |
| `~/.config/omarchy/shell.json` | User bar / Settings layout | `deploy.sh` once if missing |
| `~/.config/omarchy/themes/` | User theme overlays | user (install leaves empty) |
| `~/.config/omarchy/plugins/` | Community / third-party plugins | user (`omarchy-plugin-add` or rsync) |
| `~/.xsessionrc` | Exports `OMARCHY_PATH` and prepends `bin` to `PATH` | `deploy.sh` |
