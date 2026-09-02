# Phase 5 — panels (build log)

The 6 `kind: bar-widget` panels, unblocked by Phase 8's `summonBarWidget`.
Each `Panel.qml` uses `Ui/Panel` + `Ui/KeyboardPanel` (T1 already done in
Phase 2), mounts in the real bar via `BarWidgetRegistry`, and is summoned by
`omarchy-shell -q shell toggle omarchy.<x>`.

## Done — bluetooth · network · power (2026-08-31)

### `omarchy.bluetooth`  (`plugins/panels/bluetooth/`, 1045→978 lines)

- `Quickshell.Bluetooth` (BlueZ/DBus) — **present** in the local QS build,
  used as-is for adapter/device state and `adapter.discovering`.
- **X11 delta:** dropped `import Quickshell.Services.Pipewire` + the
  auto-route-audio-to-a-new-BT-sink block (`audioSinks` / `bluetoothAudioSink`
  / `setDefaultAudioSink` / `scheduleAudioOutputSwitch` /
  `switchPendingAudioOutput` / `audioSwitchTimer` / 3 props). PulseAudio's
  `module-switch-on-connect` covers that.
- **Vendored:** `bin/omarchy-bluetooth-device` (verbatim — pure
  `bluetoothctl`), `bin/omarchy-bluetooth-power` (adapted — `rfkill` guarded,
  falls back to `bluetoothctl power on/off` when `rfkill` is absent; no
  `systemd-rfkill` on Devuan so the block isn't restored on boot).

### `omarchy.network`  (`plugins/panels/network/`, 2350 lines)

- `Quickshell.Networking` (NetworkManager/DBus) — **present**, used as-is.
- **X11 deltas:** `wl-copy` → `xclip -selection clipboard` (xsel fallback);
  `omarchy-launch-floating-terminal-with-presentation` → `i3_term --float -e`.
- **Vendored verbatim:** `omarchy-network-status` (ip/nmcli/awk),
  `omarchy-network-band`, `omarchy-network-password`, `omarchy-network-qr`.
- **`omarchy-dns`** vendored + softened: `systemctl is-active
  NetworkManager` → `sv`/`service`/`pgrep` probe; `systemctl reload
  systemd-resolved` → `resolvconf -u`. The `nmcli connection modify` core
  works; the reload half is best-effort on Devuan.

### `omarchy.power`  (`plugins/panels/power/`, 640 lines)

- `Quickshell.Services.UPower` — **present**, used as-is. This is the
  **battery + power-profile** panel (not a session menu).
- **Vendored verbatim:** `omarchy-battery-status`, `omarchy-battery-present`,
  `omarchy-battery-low`, `omarchy-power-present`, `omarchy-system-stats`.
- `omarchy-powerprofiles-{list,set,init}` vendored verbatim — need
  `powerprofilesctl` (`power-profiles-daemon`); absent → empty profile list,
  panel still shows battery. **No battery on this VM** (`omarchy-battery-present`
  → rc 1), so the panel's `KeyboardPanel` (`open: opened && batteryPresent`)
  stays closed here — verify on a laptop.

## Wiring

- `shell.json` bar layout: `omaxian.bluetooth`→`omarchy.bluetooth`,
  `omaxian.network`→`omarchy.network`, `omaxian.battery`→`omarchy.power`. The
  `omaxian.*` widgets stay registered (rollback) but out of the layout.
- `02_keybindings.conf`: `Super+Ctrl+B` (was `rofi_bluetooth`) /
  `Super+Ctrl+W` (was `network_menu`) / `Super+Ctrl+P` (was `rofi_powermenu`)
  → `omarchy-shell -q shell toggle omarchy.<x>`. `Super+Escape` stays
  `rofi_powermenu` (the session menu — a different thing).

## Smoke (2026-08-31)

`quickshell -p <repo>` loads clean with all three; deployed + host restarted:
no errors, all three IPC-toggle, `omarchy-network-status` → `ethernet eth0`.
**Live-verify:** open each from `Super+Ctrl+{B,W,P}` or a bar-pill click —
device list / wifi list / battery render, connect/disconnect works,
click-outside dismissal per the Phase 8 known limitation.

## weather — done 2026-08-31

`plugins/panels/weather/` (`manifest.json`, `BarWidget.qml`, `Model.js`,
`Panel.qml`, `status.sh`) mirrored **verbatim** — the panel is already X11-safe
(`Panel` + `KeyboardPanel` + `FileView` + `curl` to wttr.in / open-meteo /
open-meteo geocoding; no Wayland/Hyprland/Pipewire). Scripts vendored verbatim
to `bin/`: `omarchy-weather-{status,location,icon}`, `omarchy-notification-weather`,
`omarchy-notification-send` (pure freedesktop `busctl` → dunst; `busctl` is
present via elogind). `shell.json` right cluster: `local.weather` → `omarchy.weather`
(the UI-converged `local.weather` files stay as a disabled fallback, like
`omaxian.bluetooth`/`omaxian.network`).

Smoke: registered `enabled:true`; `omarchy-shell -q shell toggle omarchy.weather`
opens/closes rc=0, no panel errors in the log; `omarchy-weather-status` →
`Milan  ·  Temp 24°C  ·  Wind →6km/h`. **Live-verify:** the pill shows the
condition glyph; click → hero (icon + temp + FEELS/WIND/HUMID) and 3-day
forecast row; click the location label → city search + geocode pick persists to
`~/.local/state/omarchy/settings/weather.json`; right-click the pill → desktop
notification with the status line.

### `Ui/KeyboardPanel.qml` → `PopupWindow` (2026-08-31)

Opening the weather panel (and, by the same shared surface, bluetooth /
network / power) blacked the whole screen under picom v12.5 glx whenever an
app window was mapped — the T1 pass had mapped upstream's full-screen
`WlrLayershell` overlay onto a full-screen X11 `PanelWindow`, and a
full-screen transparent surface never composites there. Rewrote it on
`PopupWindow` (the `Ui/PopupCard` primitive): content-sized, positioned by an
`anchor{}` block ported from the old `cardOrigin`, `grabFocus: true` for the
`Qt::Popup` keyboard grab. Verified live: weather = 480×171 centred card at
y=35 (just below the 26px bar), bluetooth = 380×108 under its pill, screen
fully visible behind both, no black. See [deltas.md](deltas.md) row.

## audio — done 2026-08-31

Full panel on a **`pactl` backend** (the user asked whether PipeWire+Pulse
could auto-switch — moot: this QS build ships `Quickshell.Services.Pipewire`
and `.Mpris` as type-only stubs with no `.so`, and `pactl` already follows
whichever server runs, PipeWire via `pipewire-pulse`).

- `Services/Audio.qml` gained a **graph API** beside its existing minimal one
  (which `local.volume` still uses): `nodes.values` / `defaultAudioSink` /
  `defaultAudioSource` / `preferredDefaultAudioSink`+`Source`, shaped like
  `Pipewire.nodes`, built from `pactl -f json list` refreshed off a
  `pactl subscribe` stream. Node objects are reused across refreshes; each has
  a writable `audio.volume`/`audio.muted` that pushes back through `pactl`.
- `plugins/panels/audio/`: `Model.js` + `manifest.json` verbatim; `Panel.qml`
  adapted from upstream (Pipewire/Mpris/`PwObjectTracker`/`PwNodePeakMonitor`
  out; `node.id`→`node.index`; `manageIpc:false` + IpcHandler).
- **Dropped:** input VU/peak meter (no pactl equivalent); MPRIS stream-label
  enrichment (module is a stub) — per-app rows show the raw app name.
- Scripts vendored verbatim: `omarchy-audio-{output-set-default,
  input-set-default,output-sink,sink-availability,output-volume,
  output-switch}` (their `wpctl` first-choice lines no-op here).
  `omarchy-audio-tuning` → stub; `omarchy-restart-audio` → `pulseaudio -k`.
- `shell.json`: `local.volume` → `omarchy.audio`.

Smoke (screenshot-verified): 380-wide card under the audio pill, hero
(icon + "CONCERT HALL" + master switch), OUTPUT section (sink row + slider +
"100%"), INPUT section (source rows + slider). Default-device bolding,
`outputVolumeName` ladder, PopupWindow positioning all correct. **Live-verify:**
drag sliders, click a device to switch default, right-click pill = mute all,
open something that plays audio → per-app stream row with its own slider.

## mic bar indicator — done 2026-08-31

`plugins/bar/widgets/Microphone.qml` (+ manifest) mirrored: `Pipewire` →
`Audio` (`defaultAudioSource` / `nodes`), `PwObjectTracker` dropped. To keep
the "mic in use" highlight, `Services/Audio.qml` gained a 4th node kind —
`capture` (from `pactl -f json list`'s `source_outputs`, refreshed on the
same `pactl subscribe` stream). Verified: widget shows `󰍬` after the audio
pill; `pactl -f json list source-outputs` populates while `parec` runs, so
`inUse` (→ `active` highlight + "Microphone in use" tooltip) tracks live
capture. Click = mute, wheel = input volume, middle-click = open
`omarchy.audio`. In `shell.json` right cluster after `omarchy.audio`.

## clock — n/a (no port needed)

The visible-bar clock (`plugins/bar/widgets/Clock.qml`, `omarchy.clock`) is the
marcello-authored minimal X11 clock — alt-format on click, timezone menu on
right-click, **no calendar**. The calendar is the LocalHost popup-host
`Bar/widgets/Clock.qml` on IPC target `calendar` (a `PopupCard` month grid),
and `$MOD+Ctrl+$ALT+d` → `omarchy-shell -q calendar toggle` already opens it
(verified: 320×340 popup). No upstream clock panel ported; the earlier
"repoint the keybind to `omarchy.clock`" note was based on a wrong assumption
that the local clock has a calendar KeyboardPanel — it doesn't.

## Loose-end cleanup — done 2026-08-31

- **`bin/omarchy-osd`** — new shim: parses `-i <icon-name> -p <0-100> -m <msg>`
  and forwards `{icon,value,message}` to `omarchy-shell osd show` (dunstify
  fallback), so the vendored `omarchy-audio-output-{volume,switch}` scripts
  (and any other upstream script calling `omarchy-osd`) show the Quickshell OSD.
- **Dropped the dead `local.weather` / `local.volume` fallbacks**:
  `plugins/bar/widgets/{Weather,Volume}.{qml,manifest.json}` and the
  LocalHost `Bar/widgets/{Weather,Volume}.qml` deleted; the two `!widgetsOnly`
  Loader refs removed from `Bar/Bar.qml`. Kills the recurring
  `another handler is registered for target weather` warning.
- **`omarchy-restart-shell`**: `sleep 0.2` → `sleep 1` between kill and
  relaunch, so the OSD PanelWindow fully unmaps before the new instance
  incubates its own (removes the transient `target osd` double-register WARN).

## New deps

`rfkill` (optional — BT power persistence), `xclip`/`xsel` (already listed),
`qrencode` (wifi QR — already listed), `power-profiles-daemon` (optional —
`powerprofilesctl` for the power panel's profile picker).
