# Phase 4 — OSD + polkit plugins (build log)

Status: **repo work done + smoke-tested 2026-08-31.** OSD ported and loads;
polkit ported but **disabled by default** (needs the system polkit agent
turned off + a live keyboard-input test — see §3). Not yet deployed /
eyeballed.

Goal (migration §10): port `plugins/osd/` + `plugins/polkit/` (T1), enable in
`shell.json`, route volume/brightness keys through the OSD.

## 1. `plugins/osd/` — ported (T1)

`marcello/.local/share/omarchy/shell/plugins/osd/{manifest.json,OsdModel.js,Osd.qml}`.
- `OsdModel.js` — verbatim (pure JS).
- `Osd.qml` T1: dropped `import Quickshell.Wayland` and the overlay
  `PanelWindow`'s `WlrLayershell.namespace/.layer/.keyboardFocus`. Added
  `screen: Quickshell.screens[0]`, `aboveWindows: true`, `focusable: false`;
  kept `mask: Region {}` (click-through) + `exclusionMode: Ignore`. It's a
  visual-only, input-transparent overlay — the KeyboardPanel/Phase-2 T1
  pattern.
- First-party ⇒ auto-enabled by `PluginRegistry` (`__isFirstParty` →
  `isEnabled` true, no `shell.json` entry needed). `keepLoaded: true` in the
  manifest, so it's live from startup.
- IPC: `omarchy-shell osd show '{"icon":"volume","value":"45","message":""}'`.
  A non-empty `message` shows text instead of the progress bar. Icon names:
  `volume{,-low,-medium,-high,-muted}`, `microphone{,-muted}`, `brightness`,
  `keyboard`, … (see `OsdModel.js`).

### Known smoke-test WARN

Headless `quickshell -p <tree> -n` prints, right as the OSD incubates:
```
QQmlContext: Cannot set context object on invalid context.
QQmlComponent: Cannot create a component in an invalid context
```
followed by `Osd.qml: Object or context destroyed during incubation` when
`timeout` kills the run. This looks like an incubation-vs-shutdown race in
the `-n` smoke path (the panel `Instantiator` loads `Osd.qml`
`asynchronous: true`). **Verify live** that it doesn't repeat once the host
is running steadily and that `omarchy-shell osd show …` draws the overlay.

## 2. Volume / brightness → OSD

`scripts/i3_volume` + `scripts/i3_brightness` now call
`omarchy-shell osd show …` first and fall back to `dunstify` when
`omarchy-shell` is absent or the host is down.
- `i3_volume`: `notify_user` picks `volume-low/-medium/-high/-muted` by
  level; `toggle_mute` → `volume-muted "Muted"`; `toggle_mic` →
  `microphone{,-muted}`.
- `i3_brightness`: `notify_bl` → `brightness` + value.
- No keybinding changes — `XF86Audio*` / `XF86MonBrightness*` already run
  `$volume` / `$brightness`.

## 3. `plugins/polkit/` — ported (T1), **disabled by default**

`marcello/.local/share/omarchy/shell/plugins/polkit/{manifest.json,PolkitModel.js,PolkitAgent.qml}`.
- `PolkitModel.js` — verbatim. `Quickshell.Services.Polkit` is present on
  this box (`/usr/lib/x86_64-linux-gnu/qt6/qml/Quickshell/Services/Polkit`).
- `PolkitAgent.qml` T1: dropped `import Quickshell.Wayland` + the modal
  `PanelWindow`'s `WlrLayershell.*` (was `WlrKeyboardFocus.Exclusive`).
  Added `screen`, `aboveWindows: true`, `focusable: root.dialogVisible`, and
  a `focusGrab` timer that runs `scripts/focus-polkit.py` (an
  `XSetInputFocus` on the largest managed qs window — the same class of X11
  focus fix the launcher needed, since a full-screen `PanelWindow` doesn't
  reliably take window-level focus under i3).

**Why disabled:** the smoke test showed the expected conflict —
```
polkit.listener: failed to register: An authentication agent already exists
```
The session already runs `mate-polkit`/`xfce-polkit` via
`scripts/i3_polkit` (i3_autostart). Two agents can't both hold the polkit
authority. `shell.json` ships `"disabledPlugins": ["omarchy.polkit"]` so the
QS agent doesn't try to register.

**Opt-in** (after testing): (1) remove `omarchy.polkit` from
`disabledPlugins` in `~/.config/omarchy/shell.json`; (2) comment out the
`"$idir"/scripts/i3_polkit` line in `i3_autostart`; (3) re-login;
(4) trigger a real prompt (`pkexec true`, Synaptic, a mount) and **confirm
the password field accepts keystrokes**. If it doesn't, `focus-polkit.py`
needs work — revert both changes to fall back to `mate-polkit`.

## 4. Verify (live)

- `omarchy-shell osd show '{"icon":"volume","value":"30","message":""}'` →
  overlay with a 30% bar near the bottom-centre; auto-hides after ~1.2s.
- `omarchy-shell osd state` → `open` while visible.
- Volume / brightness Fn keys → the QS OSD (not dunst).
- `omarchy-shell shell listPlugins` → lists `omarchy.osd` (enabled) and
  `omarchy.polkit` (present, not enabled).
- polkit: only after the §3 opt-in.

## Deferred

- polkit enabled by default — pending the keyboard-input test.
- OSD for other events (media, keyboard-layout, screen-record) — Phase 6
  wires the indicators; the OSD IPC is ready for them now.
