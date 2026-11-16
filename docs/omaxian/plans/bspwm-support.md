# bspwm support (plan)

Status: **proposal, not started.** Nothing here has been tested on a live
bspwm session yet; bspwm/`bspc` are not part of `scripts/setup.sh`.

Goal: run the Omaxian Quickshell desktop under
[bspwm](https://github.com/baskerville/bspwm) as well as i3. **X11 only** —
bspwm is an X11 window manager, and no Wayland path is in scope.

---

## Feasibility

Quickshell ships `Quickshell.I3` (C++, talks to the i3 IPC socket) but no
bspwm module. Two ways to fill that gap:

| | A. C++ module in a Quickshell fork | B. QML service in `omaxian/` (**chosen**) |
| --- | --- | --- |
| Work | Fork Quickshell, write `Quickshell.Bspwm` modelled on the i3 module, build and package it | One `Services/Bspwm.qml` built on `Quickshell.Io` (`Process` + `SplitParser`) |
| Upkeep | Rebase on every Quickshell release; the Debian `quickshell` package can no longer be used | Lives in this repo; shipped by `scripts/deploy.sh` |
| Speed | Native | Fine: bspwm pushes one short status line per state change |

Option B follows a pattern the shell already uses:
[`BindingMode.qml`](../../omaxian/.local/share/omarchy/shell/plugins/bar/widgets/BindingMode.qml)
streams `i3-msg -t subscribe` through a `Process`.

### Talking to bspwm

Use `bspc` subprocesses, not `Quickshell.Io.Socket` directly. bspwm's socket
protocol separates arguments with NUL bytes, and `Socket.write()` only takes a
`QString`, so it is unclear whether those bytes survive.

| Need | Command |
| --- | --- |
| Live monitor/desktop state | `bspc subscribe report` — streams lines like `WMDP-1:OI:oII:fIII:LT:TT:G:MHDMI-1:…` |
| Window list (seed) | `bspc query -T -m` (JSON tree) |
| Window list (live) | `bspc subscribe node_add node_remove node_focus node_transfer` |
| Outputs | `bspc query -M --names` |
| Actions | `bspc desktop -f <name>`, `bspc node -f <id>`, `bspc monitor -f <name>` |
| Detect session | `bspc wm -g` exits 0 |

Report line fields: `M`/`m` = focused/unfocused monitor; `O`/`o` occupied,
`F`/`f` free, `U`/`u` urgent desktop (upper case = focused); `L` layout,
`T` state, `G` flags.

---

## Mapping from `Quickshell.I3`

| i3 feature used in the shell | bspwm equivalent | Gap |
| --- | --- | --- |
| `I3.workspaces`, `focusedWorkspace.number` ([`Workspaces.qml`](../../omaxian/.local/share/omarchy/shell/plugins/bar/widgets/Workspaces.qml)) | Desktops from the report line | Desktops are named, not numbered, and each monitor has its own fixed set. Use the desktop's index as `number`. |
| `I3.focusedMonitor` ([`Bar.qml`](../../omaxian/.local/share/omarchy/shell/plugins/bar/Bar.qml) `focusedScreenName()`), `I3.monitorFor(screen)` | `M` / `m` entries | bspwm monitor names are the xrandr output names, so they match Qt screen names. |
| `i3-msg -t get_outputs` (Bar, dock) | `bspc query -M --names` / `bspc wm -d` | None |
| `I3IpcListener` window events ([`I3Windows.qml`](../../omaxian/.local/share/omarchy/shell/Services/I3Windows.qml)) | `bspc subscribe node_*` + `bspc query -T` | The tree has `className`/`instanceName` but no window title; read `_NET_WM_NAME` via `xprop` (or a helper script) and refresh it on title changes, which bspwm does not report. |
| Binding mode indicator | None (key chords live in sxhkd) | Hide the widget under bspwm. |
| Dock-type bar window + reserved space | bspwm reads `_NET_WM_STRUT_PARTIAL` | **Verify:** stacking against fullscreen windows (polybar needs `wm-restack = bspwm` for this). |

---

## Plan

### Phase 1 — WM abstraction (no behaviour change)

1. Add `shell/Services/WM.qml`: a singleton facade exposing `workspaces`,
   `focusedWorkspace`, `focusedMonitor`, `monitorFor(screen)`,
   `focusWorkspace(...)`, `windows`, `focusWindow(id)`, `outputs`,
   `hasBindingModes`.
2. Implement the i3 backend by moving the existing `Quickshell.I3` / `i3-msg`
   code behind it. Backend is chosen once at startup.
3. Switch `Workspaces.qml`, `Bar.qml`, the dock `Panel.qml`, and window-list
   consumers from `I3.*` / `I3Windows` to `WM.*`.

Ships alone; i3 behaviour must be identical. Verify per
[`agents/skills/visual-verification.md`](../../agents/skills/visual-verification.md).

### Phase 2 — bspwm backend

1. `shell/Services/Bspwm.qml`: report-line parser → monitor/desktop models;
   window tree seed + `node_*` subscription; `bspc` actions.
2. Reconnect: restart the `bspc subscribe` process when it exits (bspwm
   restart), like the existing i3 subprocess paths.
3. Backend selection in `WM.qml`: `bspc wm -g` succeeds → bspwm, else i3.
4. `BindingMode` hidden when `WM.hasBindingModes` is false.

### Phase 3 — rest of the desktop (separate work)

- `omarchy-session-is-bspwm`; audit the 7 `omarchy-*` commands that call
  `i3-msg` / `omarchy-session-is-i3`.
- Port keybinds from `omaxian/.config/i3/` to an sxhkd config, plus a
  `bspwmrc` (picom, dunst, xss-lock, polkit, Quickshell autostart).
- `scripts/setup.sh`: optional `bspwm` + `sxhkd` package set;
  `scripts/deploy.sh`: deploy `.config/bspwm/` and `.config/sxhkd/`.
- README: list the bspwm deltas from i3.

---

## Open questions

- Does the bar stay below fullscreen windows under bspwm, or does it need an
  explicit restack below the root's top-level?
- Is `bspc subscribe report` enough for urgent/occupied state on every
  monitor, or does the dock need per-desktop window counts from the tree?
- Workspace numbering: show bspwm desktop names, or a global index across
  monitors to match the i3 look?
