# Phase 8 — the real bar engine (build plan)

The keystone: port `plugins/bar/` so `BarWidgetRegistry` widgets actually
mount and `shell.bar.summonBarWidget()` works — which unblocks **Phase 5**
(the `kind: bar-widget` panels) and **Phase 6**'s `Indicators` widget.

`plugins/bar/` is ~4400 lines. `Bar.qml` alone is ~1300 and is "the single
biggest file" (§2b). §11 flags the strut-under-i3+glx-picom behaviour as an
**unknown that needs a live spike** — it may not just work.

**Stages 1–6 done in the repo (2026-08-31). Stage 7 (retire polybar +
picom) is the live deploy step.**

## Stages 3–6 — done

- **Stage 3** `plugins/bar/Bar.qml`: `Quickshell.Hyprland`→`.I3`,
  `Quickshell.Wayland` dropped, `BarPanel` `WlrLayershell.*` →
  `aboveWindows: true`, `Hyprland.focusedMonitor`→`I3.focusedMonitor`,
  `DragGhostPanel`/`BarMoveGhostPanel` + their 2 `Variants` deleted (1827→~1690
  lines; in-slot drag state left inert). `indicators/Dictation.qml` not
  mirrored; `Indicators.qml` `defaultIndicatorEntries` drops `"Dictation"`.
- **Stage 4** `Workspaces.qml` T3 (upstream widget, `I3` API); `KeyboardLayout.qml`
  = the local X11 poll version (moduleName fixed); `KeyboardLayoutModel.js`
  removed. Click-to-cycle landed later (**2026-09-03**, `keyboard.sh next` —
  see [deltas.md](deltas.md)). `ActiveWindow` / `Microphone` deferred (not in the Stage-6 layout).
- **Stage 5** `shell.qml`: S2 walked back — `import "plugins/bar"` +
  `defaultBarComponent`/`defaultBarLoader`/`pluginBarLoader` restored verbatim
  (real bar = `shell.bar`); `import "Bar" as LocalHost` + a second `Loader`
  keeps the local flat `Bar/Bar.qml` as an **invisible** popup/IPC host.
- **Stage 6** `shell.json`: `bar.enabled:true` + minimal layout
  (`workspaces` | `clock` | `keyboard-layout`, `indicators`, `tray`).

### Smoke test (repo tree, live i3)

`quickshell -p <repo>` → "Configuration Loaded". Two QS windows: the local
host at `1280x1` (no strut) + the **real bar at `1280x26` with
`_NET_WM_STRUT_PARTIAL = 0,0,26,0`**. i3 reflowed the focused ws `y: 41 → 68`
(polybar 40 + bar 26) — **strut honoured**. Clean teardown.

Benign WARNs: `omarchy-reminder: command not found` (Reminder indicator —
not vendored, Process just fails); `QQmlContext: … invalid context` (the
recurring incubation-vs-`-n`-shutdown race, seen since Phase 4).

### Stage 6 deploy (2026-08-31) — **live**

`cp -r plugins/bar` + `cp shell.qml` + `omarchy-restart-shell`.
`omarchy-shell shell listPlugins` → `omarchy.bar` + `clock`/`indicators`/
`keyboard-layout`/`tray`/`workspaces` enabled. Two QS windows: local host
`WxH×1` (no strut) + **real bar `WxH×26`, `_NET_WM_STRUT_PARTIAL = 0,0,26,0`**.
i3 ws rect `y: 41 → 67` (polybar 40 + bar 26). Both bars stacked (QS on top).
Log: "Configuration Loaded", only benign WARNs (`omarchy-reminder` not
vendored). No crash.

### Bar-fill (2026-08-31) — 10 local widgets registered

`Bar/widgets/{Weather,Volume,Bluetooth,Network,Vpn,Updates,Notifications,
Battery}.qml` copied into `plugins/bar/widgets/` (id `omaxian.<name>`,
`moduleName` fixed) with sibling manifests; `SysStats` + `Mpd` reshaped
`Row`→`BarWidget`. `Bar/Bar.qml`: `Weather` gated behind `!widgetsOnly` (its
`weather` IpcHandler was double-registering). `shell.json` layout expanded to
`workspaces | mpd, clock | weather, sysstats, keyboard-layout, volume,
bluetooth, network, vpn, updates, notifications, indicators, tray, battery`.

Deployed + live: `listPlugins` shows all 13 `omaxian.*` + `omarchy.*` widgets
enabled; bar strut 26px, i3 ws `y=67`; **no warnings** (dup handler gone).

Still LocalHost-only (round 2): `MenuButton`/`HelpButton`/`Timer`/
`WallpaperButton`/`PowerButton` + `WindowsPopup` — their IPC handlers load
unconditionally in the invisible host; need the `!widgetsOnly` gate +
registration to appear in the visible bar. Also deferred: `ActiveWindow`
(T3), `Microphone` (pactl), `SystemUpdate` (apt).

### Known limitation — widget-popup click-outside dismissal (2026-08-31)

Once popups anchor to the real `plugins/bar` dock (`_NET_WM_STATE_ABOVE`)
instead of the 1px widgets-only host, `PopupCard.grabFocus` (the `Qt::Popup`
pointer grab) **stops dismissing on a click into an application window**.
What still closes a widget popup:
- clicking the bar / re-clicking the trigger widget — handled by
  `plugins/bar/Bar.qml`'s `modulePointer.onClicked` (closes `activePopout`);
- the IPC toggle (`omarchy-shell -q <target> toggle`, the Phase-7 keybinds);
- Escape (where the widget wires it).

A full-screen transparent dismiss-catcher `PanelWindow` was tried and
reverted: under glx-picom's fullscreen unredirection it painted the screen
solid black **and** still missed clicks on windows. The real fix is the
deferred `PopupCard` → `KeyboardPanel` conversion for the widget popups,
paired with a picom `unredir-if-possible-exclude = [ "class_g = 'quickshell'" ]`
(and `KeyboardPanel` itself will need that exclude — its own full-screen
transparent surface would hit the same black-out).

### Stage 7 — done in the repo (deploy + reload to activate)

- `scripts/i3_bar` — polybar launch commented out; `killall -q polybar` added
  so `i3-msg reload` drops it. Rollback: uncomment the `polybar.sh` line +
  `bar.enabled:false`.
- **picom** — *no change needed*. `picom.conf` already excludes
  `window_type = 'dock'` from shadow, corner-radius, and shadow=false
  (lines ~342/354/382), and the QS bar is `_NET_WM_WINDOW_TYPE_DOCK`
  (verified). The planned `class_g = 'quickshell'` rule is redundant.
- Deploy `i3_bar` → `~/.config/i3/scripts/`, then `i3-msg reload` (or
  re-login). Verify: polybar gone, QS bar alone at the top, windows tile
  below it, no shadow/rounding on the bar.

### Note (2026-08-31): there is **no headless mode** in upstream `Bar.qml`

It always draws a bar and reserves strut when loaded; `bar.enabled` in
`shell.json` isn't read by it (`barHidden` only *parks* an existing surface
at runtime). So the engine can't be "loaded but invisible" by a config flag.
The strut spike (Stage 1, below) passed, so this is fine — the QS bar goes
visible from Stage 6; polybar is retired in Stage 7. Until Stage 7 both bars
render (i3 reserves the sum of their struts).

---

## Stage 1 — strut spike — **PASS (2026-08-31)**

Ran a throwaway `PanelWindow { anchors{top;left;right}; implicitHeight: 32;
exclusionMode: ExclusionMode.Auto }` under the live i3 4.24 + glx-picom
session (polybar also up):

| check | result |
|---|---|
| `_NET_WM_STRUT_PARTIAL` | `0, 0, 32, 0, …` — top strut of 32 emitted ✓ |
| `_NET_WM_STRUT` | `0, 0, 32, 0` ✓ |
| `_NET_WM_WINDOW_TYPE` | `_NET_WM_WINDOW_TYPE_DOCK` ✓ |
| i3 reflow | focused-ws rect `y: 41 → 73` (= polybar's 40 + spike's 32) — **i3 honoured the strut** ✓ |
| teardown | kill → rect back to `y: 41`, no strut leak, picom fine ✓ |

Quirk: with polybar *also* mapped, the spike landed at `Y=1` (visually
overlapping polybar) rather than below it — i3 packs simultaneous top docks
by map/stack order. **Non-issue for the end state**: once polybar is retired
(Stage 7) there's a single top dock and it sits at `Y=0`. The reserved area
is always the sum, so tiling is correct throughout.

**Verdict: the visible flip is viable.** The `class_g = 'quickshell'` picom
exclusions (Stage 7) are still recommended (shadow/rounding), not yet tested.

## Stage 2 — mirror the clean files (verbatim)

`plugins/bar/` → `marcello/.local/share/omarchy/shell/plugins/bar/`:
- **verbatim:** `BarModel.js`, `manifest.json`, `widgets/{Clock,Indicators,
  Spacer,SystemUpdate,Tray}.qml` + their `.manifest.json` + `TrayModel.js`,
  `indicators/{Dnd,NightLight,Reminder,ScreenRecording,StayAwake,TmuxAlert}.qml`.
  Drop `indicators/Dictation.qml` (Wayland `wtype`/voxinput — §6).
- These are pure QML/JS; they only do anything once the engine mounts them.

## Stage 3 — `Bar.qml` (T1 + T3, drop the ghosts)

| Change | detail |
|---|---|
| `import Quickshell.Hyprland` / `Quickshell.Wayland` | drop |
| `BarPanel` `WlrLayershell.namespace/.layer` | drop — X11 `XPanelWindow` auto-docks; keep `exclusionMode: ExclusionMode.Auto`, `anchors`, `implicitHeight` |
| `Hyprland.focusedMonitor` | `Quickshell.I3.focusedMonitor` (T3) — `import Quickshell.I3` |
| `DragGhostPanel` + `BarMoveGhostPanel` components + their 2 `Variants { model: Quickshell.screens }` blocks + all `barDrag*` / `barMove*` state | **delete** (§2b — drag-to-reorder / drag-to-move-screen; `omarchy bar set/move/position` IPC stays the only reorder path) |
| `ScreenMoveRemap` | already mirrored in `Ui/` (Phase 2) |
| bar `Variants { model: Quickshell.screens }` (the real bar) | keep — per-monitor bars via X11 RandR names |

## Stage 4 — the 4 transform widgets

marcello already has local `Bar/widgets/{Workspaces,KeyboardLayout}.qml`
(I3 / xprop-poll). Two options:
- **A:** register the *local* widgets in `BarWidgetRegistry` under the
  upstream ids (`omarchy.workspaces`, `omarchy.keyboard-layout`) via sibling
  manifests — keeps the proven X11 code.
- **B:** port the upstream widgets with the T3 transform.

Recommend **A** for Workspaces/KeyboardLayout (proven), **port** for:
- `ActiveWindow.qml` — `ToplevelManager.activeToplevel` → `i3-msg -t
  subscribe '["window"]'` (T3). New; no local equivalent.
- `Microphone.qml` — `Quickshell.Services.Pipewire` → `Services/Audio.qml`
  source side (`pactl`).

The other local `Bar/widgets/*` (Mpd, Timer, Vpn, SysStats, Weather,
Battery, Network, Bluetooth, Updates, Notifications, MenuButton, PowerButton,
HelpButton, WallpaperButton, Separator) get sibling `*.manifest.json` and
register as first-party `local` widgets (deltas.md already lists them).

## Stage 5 — reconcile `shell.qml`

Phase 3's **S2** replaced upstream's `defaultBarComponent` /
`defaultBarLoader` / `pluginBarLoader` with a `Loader` mounting the local
flat `Bar/Bar.qml`. Phase 8 walks that back:
- restore `import "plugins/bar"` + `defaultBarComponent` (`Bar { … }`) +
  `defaultBarLoader` + `pluginBarLoader` **verbatim from upstream**.
- keep S1 (`pragma UseQApplication`), S3 (no `Style.scheduleRefresh`), S4
  (no `appLibrary`).
- the local flat `Bar/` tree is retired (or kept for rollback only).
- deltas.md `shell.qml` row: S2 goes from "local bar loader" to "verbatim".

## Stage 6 — `shell.json` + §6 layout

```json
"bar": {
  "enabled": true,
  "position": "top",
  "layout": { "left": […], "center": […], "right": […] }   // §6 final layout
}
```
Headless interim: `"enabled": false` — engine still mounts widgets for
`summonBarWidget`, no surface.

## Stage 7 — the visible flip (only after Stage 1 passes)

- `scripts/i3_bar`: stop launching polybar; keep `omarchy-launch-shell`
  **without** `QS_WIDGETS_ONLY`.
- `picom.conf`: add `class_g = 'quickshell'` to `shadow-exclude` and
  `rounded-corners-exclude` (or the corresponding blocks) so the bar gets no
  double shadow / rounding.
- polybar config stays in the repo (rollback: re-add to `i3_bar`, set
  `bar.enabled=false`).
- re-check strut live: windows tile below the QS bar, no picom artefacts.

## Verify

- Headless: `omarchy-shell shell listPlugins` shows `omarchy.bar` +
  registered widgets; `Super+Ctrl+B` (Phase 7 bind, once repointed at
  `omarchy-shell -q shell toggle omarchy.bluetooth`) summons the bluetooth
  panel centred; polybar unchanged.
- Visible: QS bar renders the §6 layout, reserves strut, survives a
  monitor hotplug, no picom double-shadow; polybar gone from autostart.
- `quickshell -p <repo>` loads clean at every stage.

## Deferred / dropped

`indicators/Dictation.qml` (Wayland). Drag-ghost overlays (§2b). The
`plugins/bar/README.md` (docs only). Third-party bar plugins (none).
