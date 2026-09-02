# Phase 3 — Quickshell plugin host (build plan)

Status: **repo work done + smoke-tested 2026-08-31** (`quickshell -p <repo
tree>` → "Configuration Loaded", only the two known-benign WARNs below).
**Not yet deployed / verified live.**

Goal (migration §10): replace the 24-line stopgap `shell.qml` with a mirror
of upstream's plugin host (`shell.qml` + `services/PluginRegistry` +
`services/BarWidgetRegistry`), adapt `omarchy-launch-shell` /
`omarchy-restart-shell` for X11, ship a `shell.json` with no plugins, and
point i3 autostart at `omarchy-launch-shell`.

Verify: host runs headless (polybar still the visible bar, no QS panels);
`omarchy-shell shell ping` → `ok`; the existing polybar-click / keybind
popups (weather, powermenu, windows, launcher…) still work;
`omarchy-theme-set "X"` recolours QS live (the S3 payoff — `applyTheme` IPC
now has a real handler).

## Done (repo)

- **Repo QS tree moved** `marcello/.config/quickshell/` →
  `marcello/.local/share/omarchy/shell/` (`git mv`; §3). Path refs updated
  across `docs/`, `AGENTS.md`, `README.md`, `polybar/scripts/qs-timer.sh`.
- **`services/BarWidgetRegistry.qml` + `PluginRegistry.qml`** — mirrored
  verbatim.
- **`shell.qml`** — upstream mirror + S1–S5 (below).
- **`bin/omarchy-launch-shell`** — adapted: `systemd-cat` → append to
  `~/.local/state/omarchy/shell.log`; `hyprctl -j monitors` →
  `i3-msg -t get_version`; supervise loop + relaunch budget kept.
- **`bin/omarchy-restart-shell`** — rewritten (~25 lines): `quickshell kill`
  + `pkill` → `setsid … omarchy-launch-shell` → poll `omarchy-shell -q shell
  ping`.
- **`bin/omarchy-shell`** — vendored; only change is X11 `DISPLAY` recovery
  (scan `/tmp/.X11-unix`) in place of the Wayland-socket scan.
- **`marcello/.config/omarchy/shell.json`** — `{version:1, bar:{enabled:false},
  plugins:[], idle:{…}}`.
- **`scripts/i3_bar`** — QS launch line → `setsid nohup omarchy-launch-shell &`
  (guarded by `pgrep`), `QS_WIDGETS_ONLY=1` kept.
- **`scripts/i3_quickshell_toggle`** — now a thin `omarchy-shell -q <target>
  <method>` wrapper (12 keybind/polybar call sites unchanged).

### Known-benign WARNs at startup

1. `default shell.json load failed: 2 path=$OMARCHY_PATH/config/omarchy/shell.json`
   — upstream's system-default path; absent in this layout, `onLoadFailed` →
   `builtinShellConfig`. Harmless (matches upstream with no system default
   installed).
2. `inotifywait … could not be found` — `inotify-tools` not installed;
   `PluginRegistry.localPluginWatcher` retries every 1s. No third-party
   plugins in Phase 3, so no effect. Install `inotify-tools` to silence it
   (added to §12 deps).

---

## 1. The fork: what the mirrored `shell.qml` loads as the bar

Upstream `shell.qml`:
- `import "plugins/bar"` and instantiates upstream `Bar { }` as the default
  bar (`defaultBarComponent` / `defaultBarLoader`), plus a `pluginBarLoader`
  for a plugin-provided bar.
- `plugins/bar/Bar.qml` is the **real bar engine** — Phase 8, not ported.

The interim still needs the local `Bar/Bar.qml` running in `QS_WIDGETS_ONLY`
mode: it hosts every polybar-click / keybind popup behind an `IpcHandler`
(weather, powermenu, windows, launcher, runner, calendar, help, wallpaper).
Losing it breaks all of those.

**Decision:** mirror `shell.qml` but replace the `import "plugins/bar"` +
`defaultBarComponent`/`defaultBarLoader`/`pluginBarLoader` block with a single
`Loader` that mounts the local `Bar/Bar.qml` (widgets-only). Everything else —
`PluginRegistry`, `BarWidgetRegistry`, the panel `Instantiator`, `serviceHost`,
`summon`/`hide`/`toggle`, and every `IpcHandler` — is mirrored verbatim, so
Phase 4/5 panels have a real host to load into. `shell.bar` points at the
local bar; the bar-widget-panel routing (`summonBarWidget`,
`panelWidgetIdAt`, `toggleTransparency`, `debugBarGeometry`) is all
`typeof`-guarded upstream and degrades to `"no-bar"`/`"unknown"` until
Phase 8.

### `shell.qml` deltas (on top of the verbatim mirror)

| # | Delta | Why |
|---|---|---|
| S1 | `//@ pragma UseQApplication` at the top | Tray.qml right-click menus need QtWidgets/QMenu; upstream `shell.qml` has no pragma. deltas.md Phase-3 row. |
| S2 | bar loader → local `Bar/Bar.qml` (widgets-only); drop `import "plugins/bar"`, `defaultBarComponent`, `defaultBarLoader`, `pluginBarLoader`, `configureBar`'s upstream-Bar props | `plugins/bar` is Phase 8. |
| S3 | `shell` IPC `applyTheme`: drop the `Style.scheduleRefresh()` call (keep `Color.loadColors` / `Color.loadShell`) | Phase 2 removed `Style.scheduleRefresh` with the `drop-hyprctl` delta. This is the hook `omarchy-theme-set`'s `reload_quickshell()` (Phase 1) calls — wiring it live is the Phase 3 payoff. |
| S4 | `appLibrary` property + `AppLibrary { }` instance removed | Its only consumer is `plugins/menu` (rofi stays — decision 4, not ported). `AppLibrary.qml` needs `import Quickshell.Wayland` + a `ToplevelManager` T1 strip for no live benefit. Port it if/when a QS launcher lands. |
| S5 | `omarchyPath` / `shellPath` / `defaultsPath` comments note i3 (no uwsm; `OMARCHY_PATH` from `i3_autostart`, Phase 1) | — |

`defaultsPath` = `$OMARCHY_PATH/config/omarchy/shell.json` (upstream) has no
file in this layout — `defaultsFile` `onLoadFailed` → `builtinShellConfig`,
which is fine. `userConfigPath` = `~/.config/omarchy/shell.json` (ships, §4).

---

## 2. Services

| File | Action |
|---|---|
| `services/BarWidgetRegistry.qml` | **verbatim** (pure QtQuick, 49 lines) |
| `services/PluginRegistry.qml` | **verbatim** (716 lines; `Quickshell` + `Quickshell.Io` + `qs.Commons`, no Wayland). Scans `$OMARCHY_PATH/shell/plugins` via a bash `find` + optional `inotifywait` watch of `~/.config/omarchy/plugins`. Both dirs are empty in Phase 3 → `installedPlugins = {}` → headless. `inotifywait` missing (no `inotify-tools`) just disables live third-party reload — harmless. |
| `services/AppLibrary.qml`, `services/AppSearch.js`, `services/hidden-entries.sh` | **deferred** (S4) |

No `services/qmldir` upstream — `import "services"` is a directory import,
resolves the `.qml` files directly.

---

## 3. `$OMARCHY_PATH/shell` topology — **decided: move (option B)**

`omarchy-launch-shell` runs `quickshell -n -p "$OMARCHY_PATH/shell"`;
`PluginRegistry.firstPartyDir` = `$OMARCHY_PATH/shell/plugins`.

**Done 2026-08-31:** the repo QS tree moved
`marcello/.config/quickshell/` → **`marcello/.local/share/omarchy/shell/`**
(`git mv`, renames preserved). All `docs/` + `AGENTS.md` + `README.md` +
`polybar/scripts/qs-timer.sh` path references updated by sed.

- Deploy: `cp -r marcello/.local/share/omarchy/shell → ~/.local/share/omarchy/shell`
  (alongside the existing `bin/` copy).
- **Back-compat symlink** (deploy-time, not committed): `ln -sfn
  ~/.local/share/omarchy/shell ~/.config/quickshell` so bare `qs` /
  `quickshell` (no `-p`) still finds the config. `omarchy-shell` /
  `omarchy-launch-shell` always pass `-p "$OMARCHY_PATH/shell"` and don't
  need it.
- Scripts inside the tree that self-locate (`scripts/launch.sh` via
  `BASH_SOURCE`, every widget's `Quickshell.shellDir + "/scripts/…"`) are
  move-safe.

---

## 4. `bin/omarchy-launch-shell` (adapt for X11/Devuan)

Upstream is a supervise loop around `systemd-cat -t omarchy-shell -- quickshell
-n -p "$OMARCHY_PATH/shell"` with a `hyprctl -j monitors` liveness gate.

Adaptation:
- `systemd-cat -t omarchy-shell --` → `logger` is not a wrapper exec; use
  `quickshell … >> ~/.local/state/omarchy/shell.log 2>&1` (rotate-free, the
  file is in the never-committed state dir) **or** pipe through
  `logger -t omarchy-shell`. Keep it backgrounded + `wait` as upstream does.
- `compositor_alive()`: `hyprctl -j monitors` → `i3-msg -t get_version`
  (`>/dev/null 2>&1`), same 3× retry.
- Keep `QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1`, the relaunch budget
  (5 in 60s), the `trap stop HUP INT TERM`.
- Drop nothing else — the supervise loop is desktop-agnostic.

## 5. `bin/omarchy-restart-shell` (rewrite — X11 is trivial)

Upstream is ~90 lines of Hyprland instance-signature discovery + lock-state
preservation (`omarchy-hyprland-session-locked`, `omarchy-shell lock status`).
None applies (lock dropped). Replace with:

```
#!/bin/bash
# omarchy:summary=Restart the Omarchy shell (X11 port)
set -euo pipefail
: "${OMARCHY_PATH:=$HOME/.local/share/omarchy}"
CONFIG_DIR="$OMARCHY_PATH/shell"
[[ -f $CONFIG_DIR/shell.qml ]] || { echo "shell config not found: $CONFIG_DIR" >&2; exit 1; }
while timeout 5 quickshell kill -p "$CONFIG_DIR" >/dev/null 2>&1; do :; done
pkill -f "quickshell .*-p $CONFIG_DIR" 2>/dev/null || true
setsid nohup omarchy-launch-shell >/dev/null 2>&1 &
for _ in $(seq 1 40); do
  omarchy-shell shell ping >/dev/null 2>&1 && exit 0
  sleep 0.1
done
echo "Omarchy shell did not become ready after restart." >&2
exit 1
```

(`omarchy-shell` is the existing IPC wrapper — verify it's vendored / a thin
`quickshell ipc call "$@"` shim; add one if not.)

## 6. `~/.config/omarchy/shell.json` (new — `marcello/.config/omarchy/shell.json`)

```json
{
  "version": 1,
  "bar": { "enabled": false },
  "plugins": [],
  "idle": { "screensaver": 150, "lock": 300 }
}
```

`bar.enabled` isn't read by the interim local `Bar/Bar.qml` (it self-selects
on `QS_WIDGETS_ONLY`); it's here for forward-compat and to make the intent
explicit. The mirrored host reads `bar` for `barConfig` but with no
`plugins/bar` there's nothing to configure yet.

## 7. i3 autostart rewiring

`scripts/i3_bar` currently does `bash themes/polybar.sh` + launches QS via
`$QS_LAUNCH` / `REPO_QS` with `QS_WIDGETS_ONLY=1`. Replace the QS launch line
with:

```
pgrep -f "quickshell .*/shell" >/dev/null || QS_WIDGETS_ONLY=1 omarchy-launch-shell &
```

Keep `QS_WIDGETS_ONLY=1` in the env until Phase 8 (the mirrored `shell.qml`'s
local-bar `Loader` passes it to `Bar/Bar.qml`). `OMARCHY_PATH` + `PATH` are
already exported by `i3_autostart` (Phase 1).

`omarchy-restart-shell` replaces the old `scripts/i3_quickshell_toggle`
restart path.

---

## 8. Remaining — on the live machine

A. **Deploy**:
   - **`cp marcello/.xsessionrc ~/.xsessionrc`** then re-login. This is the
     real PATH fix: lightdm sources `~/.xsessionrc` *before* i3, so `omarchy-*`
     land on the PATH i3 keybinds / polybar clicks inherit. An `export` in
     `i3_autostart` never did (it only reaches that script's own children) —
     which is why the volume OSD fell back to dunst and `omarchy-shell` was
     "not found" in terminals.
   - `cp -r marcello/.local/share/omarchy/{shell,bin} ~/.local/share/omarchy/`
     (the `bin/` copy now includes `omarchy-{launch,restart}-shell` +
     `omarchy-shell`).
   - `cp marcello/.config/omarchy/shell.json ~/.config/omarchy/shell.json`
   - `ln -sfn ~/.local/share/omarchy/shell ~/.config/quickshell` (back-compat
     for bare `qs`; optional).
   - deploy `marcello/.config/i3/scripts/{i3_bar,i3_quickshell_toggle}` →
     `~/.config/i3/scripts/`.
   - `apt install inotify-tools python3-xlib` — `inotify-tools` silences
     WARN 2; **`python3-xlib` is required** for the launcher/runner search
     boxes (`scripts/focus-window.py` does the `XSetInputFocus`; without it
     typing in those popups does nothing).
   - `scripts/focus-window.py` fix: its `pgrep` target changed from
     `^quickshell -d` to `pgrep -x quickshell` — `omarchy-launch-shell` runs
     `quickshell -n -p …`, not `-d`.
B. **Restart the session** (re-login) or: `pkill -f 'quickshell.*/quickshell';
   pkill -f 'quickshell.*/omarchy/shell'` then `~/.config/i3/scripts/i3_bar`.
C. **Verify headless**:
   - `omarchy-shell shell ping` → `ok`
   - `omarchy-shell shell listPlugins` → `[]`
   - polybar clicks + `Super+L`/`Alt+F2`/`Super+X`/`Super+W` still open their
     popups (routed through `i3_quickshell_toggle` → `omarchy-shell`).
   - `omarchy-theme-set "Gruvbox"` → QS popups recolour **without restart**
     (S3: `applyTheme` IPC now lands; `Color.loadColors`/`loadShell` run).
   - `~/.local/state/omarchy/shell.log` gets the QS stderr/stdout.
D. `omarchy-restart-shell` works from a terminal (kills + relaunches +
   `ping` succeeds).

Rollback: `git revert` the move + `shell.qml`; re-point `i3_bar` at
`scripts/launch.sh` (still in the tree). polybar is unaffected throughout.

## 9. Deferred out of Phase 3

`AppLibrary` / `AppSearch.js` (S4); the real `plugins/bar` engine (Phase 8);
every actual plugin (`osd`/`polkit` Phase 4, panels Phase 5, services
Phase 6).
