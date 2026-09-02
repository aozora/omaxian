# Phase 6 — services + indicators (build log)

The `Indicators` bar widget + its 6 indicators were mirrored in Phase 8 but
render nothing without their backing services. This phase lights up the three
that matter on X11.

## Done — indicator list trim + Dnd / NightLight / StayAwake (2026-08-31)

### `plugins/bar/widgets/Indicators.qml`

`defaultIndicatorEntries` trimmed to **`["NightLight", "Dnd", "StayAwake"]`**.
Dropped: `Dictation` (Wayland, Phase 8), `Reminder` (`omarchy-reminder` not
vendored — was spamming the log), `ScreenRecording` (no screen-recorder set
up on this box). Re-add any via `shell.json`'s indicator settings once its
script exists.

### `Dnd.qml` — dunstctl (decision 4)

Upstream reads/toggles DND on the ported-out `omarchy.notifications` service.
This profile keeps dunst, which owns the same state: 5s poll of
`dunstctl is-paused`, `onPressed` → `dunstctl set-paused true|false`.

### `plugins/services/nightlight/` — redshift (T-adapt)

- `manifest.json`, `NightlightModel.js` — verbatim.
- `Service.qml` — `hyprsunset` / `hyprctl hyprsunset` → `redshift`:
  `redshift -P -O <temp>` for night, `redshift -x` for day. redshift is
  stateless, so the applied temperature is tracked in
  `~/.local/state/omarchy/nightlight.temp` (read on probe, written on apply).
  `enabled = temp < 6000` (NightlightModel threshold). IpcHandler
  `status`/`refresh`/`enable`/`disable`/`toggle` kept.
- `bin/omarchy-toggle-nightlight` vendored + adapted (redshift + same state
  file) for the CLI / a future keybind.

### `plugins/services/idle/` — minimal stay-awake (§2b drop-IdleMonitor)

Upstream is a 360-line Hyprland `IdleMonitor` service (idle → screensaver
window / lock / DPMS). This profile does **manual lock only** (AGENTS.md), so
the idle-lock automation is dropped entirely. The port keeps just what
`StayAwake.qml` needs:
- `stayAwake` bool ← `~/.local/state/omarchy/indicators/stay-awake`
- `setIdleEnabled(current)` / IpcHandler `toggle` → flips it and runs
  `xset s off -dpms` (on) / `xset s on +dpms; xset s default` (off)
- re-asserts `xset s off` on a session that had it on

## Verify (live)

- bar shows the 3 indicator glyphs; each reveals on hover / when active.
- `omarchy-shell nightlight status` → `{"enabled":false,"temperature":6500}` ✓
- `omarchy-shell idle status` → `{"stayAwake":false}` ✓
- click `Dnd` → dunst pauses (`dunstctl is-paused` → true), glyph goes active.
- click `NightLight` → screen warms (`redshift -O 4000`), glyph active.
- click `StayAwake` → `xset q` shows screensaver/DPMS off, glyph active.

## Deferred

- `plugins/services/media/` (836 lines, `Pipewire`) — **not ported.**
  `omaxian.media` talks to MPRIS directly (MPD via `mpDris2`). `local.mpd` retired.
- `plugins/services/battery/` (clean, UPower) — feeds the Phase-5 `omarchy.power`
  panel, which already carries its own battery reads; port if a bar battery
  indicator is wanted.
- Full idle→lock automation (screensaver, `xss-lock`/`xautolock`).
- `ScreenRecording` / `Reminder` / `TmuxAlert` indicators — need a recorder
  setup / `omarchy-reminder` / `omarchy-tmux-alert`.
