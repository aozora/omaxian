# `omarchy-plugin-check` — vet a community plugin before installing

Community Omarchy shell plugins are written for stock Omarchy (Arch + Hyprland +
Wayland + PipeWire + systemd). This port replaced all of those, so a plugin that
runs upstream may do nothing — or black out the screen — here.

`omarchy-plugin-check` is a **static analyzer** for that question. It reads a
plugin's `manifest.json` and its QML/JS/shell sources and reports every platform
coupling this port had to transform away, classified by whether a known fix
exists.

- Repo path: `omaxian/.local/share/omarchy/bin/omarchy-plugin-check`
- Deployed to: `~/.local/share/omarchy/bin/omarchy-plugin-check` (on `PATH`)
- Local-only — no upstream counterpart. Complements upstream's
  `omarchy-plugin-validate` (schema only), which is **not** vendored in this port.

It **never** installs, enables, clones into `~/.config/omarchy/plugins/`, or runs
any plugin code.

---

## Usage

```
omarchy-plugin-check <plugin-dir>
omarchy-plugin-check <git-url> [--ref <branch|tag|sha>]
omarchy-plugin-check <owner/repo>            # shorthand for github.com/owner/repo
```

| Option | Effect |
|---|---|
| `--ref <r>` | check out branch/tag/sha after cloning (default: repo HEAD, shallow clone) |
| `--json` | machine-readable report on stdout |
| `--keep` | keep the clone and print its path instead of deleting it |
| `--verbose`, `-v` | also list the desktop-agnostic APIs the plugin uses that work as-is |
| `-h`, `--help` | usage |

A git URL / `owner/repo` is cloned to a temp dir and removed on exit (unless
`--keep`). A local path is read in place.

## Exit codes

| Code | Verdict | Meaning |
|---|---|---|
| `0` | **compatible** | manifest valid; no blockers; no known-transform patches needed |
| `1` | **needs patching** | only couplings that have a known transform (T1/T2/T3/pactl/apt/…) |
| `2` | **incompatible** | a coupling with no X11 backend, **or** an invalid manifest |

Use it in scripts: `omarchy-plugin-check "$url" --json | jq -e '.exit == 0'`.

## What it checks

### 1. Manifest

Mirrors the checks in `services/PluginRegistry.qml` (and upstream
`omarchy-plugin-validate`): `schemaVersion == 1`; required `id name version
kinds entryPoints`; `id` matches `^[A-Za-z0-9][A-Za-z0-9._-]*$` and is **not** in
the reserved `omarchy.*` namespace; `kinds` non-empty; every entry point is a
safe relative path that exists; each declared kind has its matching
`entryPoints.*` key (`bar`→`bar`, `bar-widget`→`barWidget`, `menu`→`menu`,
`overlay`→`overlay`, `panel`→`panel`, `service`→`service`); no symlinks anywhere
in the tree.

Any manifest failure forces exit `2` — `PluginRegistry` would reject the plugin
outright.

### 2. Source scan

Greps every `*.qml` / `*.js` plus all text files, classifying hits:

| Class | Triggers | Fix the report points to |
|---|---|---|
| **BLOCK** (no X11 backend) | `IdleMonitor` | none — no `ext-idle-notify` on X11 |
| | `WlSessionLock` / `WlSessionLockSurface` | none — use `i3lock` |
| | `ToplevelManager` / `activeToplevel` / `.toplevels` / `Screencopy` | none — would need `i3-msg -t get_tree` rework |
| **PATCH** (known transform) | `import Quickshell.Hyprland`, `Hyprland.*` | **T3** → `Quickshell.I3` |
| | `WlrLayershell`, `WlrKeyboardFocus`, `import Quickshell.Wayland` | **T1** → plain `PanelWindow`/`PopupWindow` (full-screen → `Ui/CenteredModal`) |
| | `HyprlandFocusGrab` | **T2** → `PopupWindow.grabFocus` |
| | `Quickshell.Services.Pipewire`, `PwNode`, `wpctl`, `pw-dump` | route via `Services/Audio.qml` (pactl) |
| | `hyprctl`, `hyprpm`, `hyprpaper`, `hyprlock`, `swaybg`, `swaymsg` | `i3-msg` / `xrandr` / `picom` |
| | `pacman`, `yay`, `paru`, `checkupdates`, `makepkg` | `apt` / `apt list --upgradable` |
| | `systemctl`, `systemd-run`, `systemd-cat`, `journalctl`, `uwsm` | `setsid` / `sv` / `loginctl` (elogind) |
| | `wl-copy`, `wl-paste`, `wl-clipboard`, `cliphist` | `xclip` / `xsel` |
| | `grim`, `slurp`, `wl-screenrec`, `wf-recorder` | `maim` / `slop` / `ffmpeg` |
| | `walker`, `wofi`, `fuzzel`, `tofi`, `bemenu` | `rofi` |
| | `Quickshell.Services.Greetd` | n/a on this port |
| **NOTE** (`--verbose` only) | `Quickshell.Services.{Mpris,Notifications,UPower,Polkit,SystemTray}`, `Quickshell.{Bluetooth,Networking}` | desktop-agnostic — works as-is |

Each finding prints `file:line` + the source snippet. Transform ids (`T1`/`T2`/
`T3`/…) are defined in
[`../omarchy-port/omarchy-migration.md`](../omarchy-port/omarchy-migration.md) §2
and catalogued per-file in
[`../omarchy-port/deltas.md`](../omarchy-port/deltas.md).

### Why "no import error" is not enough

The Quickshell build here **does** ship `Quickshell.Hyprland`,
`Quickshell.Wayland` (incl. `WlrLayerShell`, `ToplevelManagement`, `IdleNotify`)
and `Quickshell.Services.Pipewire`. Those imports *resolve* — the plugin loads
with no error — but under i3/X11 they silently do nothing (no Hyprland IPC
socket, layer-shell surfaces don't composite under picom, idle-notify never
fires). That is exactly why this tool scans the source instead of just loading
the plugin and watching the log.

## Reading the result

- **compatible (0)** — pure QML + `Quickshell.Io` + desktop-agnostic services +
  `FileView`, and any scripts it shells out to are cross-distro. Safe to install
  as-is.
- **needs patching (1)** — fork the plugin into your own repo, apply the
  transforms the report names, keep a short delta note (same discipline as
  `deltas.md`). Then install your fork.
- **incompatible (2)** — depends on `IdleMonitor` / `WlSessionLock` /
  `ToplevelManager`, or the manifest is malformed. Not worth pursuing without a
  substantial rewrite.

**Static analysis has blind spots**: it won't catch a Wayland assumption hidden
behind an `eval`, a downloaded binary, or a runtime `Qt.createQmlObject`. And
plugins run **unsandboxed inside the long-lived shell process** — read the source
yourself before enabling, whatever the verdict.

## Examples

```console
$ omarchy-plugin-check ./my-weather-plugin
VERDICT: COMPATIBLE  (exit 0)

$ omarchy-plugin-check acme/omarchy-cava --verbose
NEEDS PATCHING — known transform exists (1)
  layer-shell     fix: T1 -> plain PanelWindow/PopupWindow ...
      Cava.qml:14   WlrLayershell.layer: WlrLayer.Bottom
VERDICT: NEEDS PATCHING  (exit 1)

$ omarchy-plugin-check https://github.com/acme/omarchy-lockfx.git --json | jq .verdict
"incompatible"
```

## Installing a plugin that passes

The `omarchy plugin add/enable/list` CLIs are **not vendored** in this port —
install by hand:

```bash
git clone <url> ~/.config/omarchy/plugins/<id>      # dir name must equal the manifest id
```

then reference `<id>` in `~/.config/omarchy/shell.json`:

| Plugin kind | Where it goes in `shell.json` |
|---|---|
| `bar-widget` | a `{ "id": "<id>" }` entry in `bar.layout.left` / `.center` / `.right` |
| `panel`, `overlay`, `service` | the top-level `"plugins": []` array |
| `bar` | `"bar": { "id": "<id>" }` |

Then `omarchy-restart-shell` and watch `~/.local/state/omarchy/shell.log` for
`PluginRegistry` warnings and QML load errors. To turn a plugin off without
removing it, add its id to `"disabledPlugins": []`.

See also [`customize/bar.md`](customize/bar.md) for the `shell.json` bar layout
and [`../omarchy-port/upstream-tracking.md`](../omarchy-port/upstream-tracking.md)
for the transform workflow this tool feeds into.
