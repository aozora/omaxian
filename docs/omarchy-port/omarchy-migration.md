# Omarchy → omaxian full-rework migration plan

Supersedes the eww-era plan in [../quickshell/README.md](../quickshell/README.md) /
[../quickshell/widget-mapping.md](../quickshell/widget-mapping.md) /
[../quickshell/theming.md](../quickshell/theming.md), which stay as history. This is the plan for a
**full rework of `omaxian/` (then named `marcello/`) to track `omarchy-quattro/` as upstream**, on a
strict **X11 + i3wm + picom + Quickshell** stack (no Wayland, no Hyprland, no
wlroots, no PipeWire, no systemd).

**Live state** is [`deltas.md`](deltas.md), not this file. Several locked
decisions below were later reversed (polybar and rofi retired; the QS bar is
the bar). Paths written as `marcello/` mean today's `omaxian/`.

Upstream reference: `omarchy-quattro/` — Omarchy **v4.0.2** (`omarchy-quattro/version`).
Treat that tree as read-only vendored upstream; never edit it. Pin is
`OMARCHY_UPSTREAM_REF` in `setup.sh` / `install.sh` (see
[upstream-tracking.md](upstream-tracking.md)).

---

## 0. Locked decisions

| #   | Decision                 | Choice                                                                                                                                                                                                                                                                                                                    |
| --- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Quickshell architecture  | **Full plugin host.** Mirror `shell.qml` + `services/PluginRegistry.qml` + `services/BarWidgetRegistry.qml` + `shell.json` + `plugins/<id>/manifest.json`. `marcello/.local/share/omarchy/shell/` becomes a near file-for-file mirror of `omarchy-quattro/shell/`; every X11 deviation is an isolated, documented delta.  |
| 2   | Paths & helper scripts   | **Mirror omarchy paths.** Use `~/.config/omarchy/` and `~/.local/state/omarchy/` exactly as upstream. Vendor the needed `bin/omarchy-*` scripts into `marcello/bin/`, adapted for Devuan/X11 (apt, elogind/`loginctl`, `xrandr`, `i3-msg`, `picom`, `pactl`).                                                             |
| 3   | i3 keybindings           | **Adopt omarchy's Super-centric scheme** as closely as i3 allows. §9 is the full three-column diff and the final map.                                                                                                                                                                                                     |
| 4   | Notifications & launcher | **Keep dunst + rofi.** QS notification button only shells `dunstctl`; rofi stays launcher/runner/powermenu/help. `plugins/notifications`, `plugins/menu`, `plugins/emojis`, `plugins/clipboard` are **not** ported in this pass.                                                                                          |
| 5   | Theme fan-out            | **WM chrome + terminals + GTK only.** `omarchy-theme-set` re-themes i3, polybar, rofi, dunst, picom, alacritty/kitty, GTK appearance, and Quickshell (live). **Not** VS Code / nvim / helix / obsidian (editors). `btop` / `chromium` are wired but **off by default** (cheap `.tpl` already exists — flip on if wanted). |
| 6   | System-stats bar         | **Keep 3 separate readouts** (`cpu`, `gpu`, `memory`) — do **not** port `plugins/panels/monitor` or consolidate. `SysStats` stays a local widget rendering the three values.                                                                                                                                              |
| 7   | AI-agent usage           | **Not ported.** `plugins/agents` + `plugins/model-usage` skipped; no `omarchy-agent-usage-*` collectors vendored.                                                                                                                                                                                                         |
| 8   | CLI-app keybinds         | **Drop the `Alt+Ctrl+*` cluster** (yazi / btop / music). btop → `Super+Ctrl+T`; music → `Super+Shift+M`; yazi → via `omarchy-menu` (or a bind chosen later).                                                                                                                                                              |
| —   | Bar (interim)            | **Keep polybar** as the visible bar. Quickshell runs as the plugin-host popup/OSD/panel provider (`QS_WIDGETS_ONLY=1`-style, but now via `shell.json` with an empty/hidden `bar` plugin). Comment out polybar modules that have no Omarchy widget behind them (§8).                                                       |

---

## 1. What upstream ships (v4.0.2 inventory)

```
omarchy-quattro/
  version                       4.0.2
  bin/            ~260 omarchy-* CLI scripts (theme, bar, audio, bluetooth, wifi, capture, menu, agent…)
  default/themed/ 17 *.tpl color templates (alacritty, kitty, foot, ghostty, btop, chromium,
                  claude, helix, neovim, vscode, obsidian, hyprland, keyboard.rgb, shell.toml, …)
  install/        Arch/Hyprland installer (reference only — not ported)
  manual/         end-user docs; 07-hotkeys.md is the keybinding source of truth
  themes/         22 themes, each: colors.toml (28 tokens, mode=light|dark) + backgrounds/
                  + icons.theme + optional neovim.lua/vscode.json/btop.theme/chromium.theme
  shell/          the Quickshell "omarchy-shell" — the thing we mirror
    shell.qml                    ShellRoot host: plugin discovery, shell.json, IPC summon/hide/toggle
    services/PluginRegistry.qml  discover + validate plugins, enabled-state from shell.json
    services/BarWidgetRegistry.qml unified 1p+3p bar-widget registry
    services/AppLibrary.qml + AppSearch.js  desktop-entry scanner (launcher backend)
    services/BarWidgetRegistry / PluginRegistry — pure QML/JS/FileView, NO Wayland
    Commons/     Color.qml Style.qml Border.qml BorderGeometry.js Util.qml qmldir  (singletons)
    Ui/          ~33 controls (Button, Panel, Dropdown, Toggle, PanelSlider, PopupCard, …)
    plugins/
      bar/            Bar.qml engine + widgets/{ActiveWindow,Clock,Indicators,KeyboardLayout,
                      Microphone,Spacer,SystemUpdate,Tray,Workspaces} + indicators/{Dnd,NightLight,
                      Reminder,ScreenRecording,StayAwake,TmuxAlert,Dictation}
      panels/         audio bluetooth clock disk-speedtest dropbox monitor network power
                      speedtest tailscale weather wifiqr
      agents/ model-usage/   AI coding-assistant usage meters
      osd/            volume/brightness on-screen display
      polkit/         themed polkit agent
      notifications/  full freedesktop notification daemon        (NOT ported this pass)
      menu/           structured command palette (omarchy-menu.jsonc) (NOT ported this pass)
      background/ lock/ idle/ clipboard/ emojis/ image-picker/ dev-gallery/ reminders/
                      services/{battery,idle,media,nightlight,tmux}
```

---

## 2. Platform-dependency audit

Every non-QML-portable coupling in `shell/`, by file, with the required X11
transform. Counts are `import Quickshell.Wayland|Hyprland` + `WlrLayershell` +
`WlSessionLock` + `IdleMonitor` + `HyprlandFocusGrab` + `ToplevelManager` +
`Pipewire` hits.

### 2a. The three standard transforms

Almost every hit is one of these mechanical swaps — already prototyped in the
current `marcello/.local/share/omarchy/shell/Ui/PopupCard.qml` and `Bar/widgets/Workspaces.qml`:

- **T1 — layer-shell window → X11 dock/overlay.** `PanelWindow { WlrLayershell.namespace/.layer/.keyboardFocus }` →
  `PanelWindow` with no `WlrLayershell` block. `Quickshell.I3`-backed `PanelWindow` on X11 is `XPanelWindow`
  (`src/x11/panel_window.cpp`): `exclusiveZone` emits a real `_NET_WM_STRUT_PARTIAL`; layering is via
  `_NET_WM_WINDOW_TYPE` (`Dock`/`Utility`) + `aboveWindows`. Drop `.namespace`. Replace `.keyboardFocus`
  with `focusable: true` and let Qt/X11 map-focus handle it.
- **T2 — click-outside dismissal.** `PanelWindow` + `HyprlandFocusGrab { active; onCleared: close() }` →
  `PopupWindow` + its built-in `grabFocus` (works on X11). Already implemented in `Ui/PopupCard.qml`
  locally (`triggerMode: "click"` path) — reuse it everywhere upstream uses `HyprlandFocusGrab`. For
  overlays that must be true top-level windows (not anchored popups), fall back to a transparent
  full-screen window that closes on click / on losing `active`.
- **T3 — workspace/monitor/IPC source.** `Quickshell.Hyprland` (`Hyprland.workspaces`, `.focusedMonitor`,
  `.dispatch`) → `Quickshell.I3` (`I3.workspaces`, `I3.focusedMonitor`, `I3.dispatch({...})`,
  `I3.findWorkspaceByName`). Structurally 1:1 for workspaces/monitors. **No** X11 analogue for a raw
  window/toplevel list — use `i3-msg -t get_tree` / `-t subscribe '["window"]'`.

### 2b. Per-file map

| File                                     | Hits | Coupling                                                                                   | Action                                                                                                                                                                                                                                                                                                                                                                |
| ---------------------------------------- | ---- | ------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `plugins/bar/Bar.qml`                    | 10   | `WlrLayershell` on bar + 2 drag-ghost overlays; `Hyprland.focusedMonitor`                  | **Port with rework.** T1 for the bar surface (`exclusiveZone`), T3 for monitor. **Drop the drag-ghost/move-ghost overlay windows** (bar drag-to-reorder / drag-to-move-screen) — cosmetic; keep `omarchy bar set/move/position` IPC as the only reorder path. This is the single biggest file. Interim: bar plugin stays disabled (polybar visible), so this can lag. |
| `Ui/KeyboardPanel.qml`                   | 7    | `WlrLayershell` + `WlrKeyboardFocus.Exclusive`                                             | T1. Local X11 version already exists in `marcello/.local/share/omarchy/shell/Ui/KeyboardPanel.qml` — reconcile with upstream, keep the X11 focus path.                                                                                                                                                                                                                |
| `services/AppLibrary.qml`                | 7    | `ToplevelManager` **only** for launch-feedback (spinner until the launched window appears) | Port the desktop-entry scan/search as-is; **delete the `ToplevelManager` launch-feedback branch** (fire-and-forget launch, like today).                                                                                                                                                                                                                               |
| `plugins/panels/audio/Panel.qml`         | 6    | `Quickshell.Services.Pipewire` (`Pipewire.defaultAudioSink/Source`, `PwNodeLinkTracker`)   | **Rebuild against `pactl`.** Reuse the local `Services/Audio.qml` (pactl subscribe-loop, sink+source, `volume/muted/setVolume()/toggleMute()` API). Keep the upstream Panel **layout**; swap its data source.                                                                                                                                                         |
| `plugins/lock/Service.qml`               | 6    | `WlSessionLock` / `WlSessionLockSurface`                                                   | **Drop.** No X11 backend in QS 0.3.0. Keep `i3lock` (`scripts/i3_lock`). Idle-triggered lock via `xss-lock`/`xautolock` outside QS.                                                                                                                                                                                                                                   |
| `Ui/SpeedTestOverlay.qml`                | 4    | `WlrLayershell` overlay                                                                    | T1. Only needed if `panels/{speedtest,disk-speedtest}` are enabled (optional).                                                                                                                                                                                                                                                                                        |
| `plugins/panels/wifiqr/Panel.qml`        | 4    | `WlrLayershell` overlay                                                                    | T1. Data path (`nmcli`/`qrencode`) is fine.                                                                                                                                                                                                                                                                                                                           |
| `plugins/reminders/ReminderFlow.qml`     | 4    | `WlrLayershell` overlay                                                                    | T1. Logic is file-backed, desktop-agnostic.                                                                                                                                                                                                                                                                                                                           |
| `plugins/polkit/PolkitAgent.qml`         | 4    | `WlrLayershell` overlay; `PolKit` agent is DBus                                            | T1. Otherwise portable — low effort, high value.                                                                                                                                                                                                                                                                                                                      |
| `plugins/osd/Osd.qml`                    | 4    | `WlrLayershell` overlay                                                                    | T1. Pair with `Services/Audio.qml` + `xbacklight`/`brightnessctl`.                                                                                                                                                                                                                                                                                                    |
| `plugins/notifications/Service.qml`      | 4    | `WlrLayershell` toast windows; daemon is DBus                                              | **Not ported this pass** (decision 4).                                                                                                                                                                                                                                                                                                                                |
| `plugins/menu/Menu.qml`                  | 4    | `WlrLayershell` overlay                                                                    | **Not ported this pass** (decision 4).                                                                                                                                                                                                                                                                                                                                |
| `plugins/image-picker/ImagePicker.qml`   | 4    | `WlrLayershell` + `WlrKeyboardFocus`                                                       | Defer. Background/wallpaper picking via `scripts/wallpapers-list.py` + `feh`/`xwallpaper` for now.                                                                                                                                                                                                                                                                    |
| `plugins/emojis/Emojis.qml`              | 4    | `WlrLayershell` overlay                                                                    | **Not ported this pass.** Use `rofimoji`.                                                                                                                                                                                                                                                                                                                             |
| `plugins/clipboard/Clipboard.qml`        | 4    | `WlrLayershell` + `wl-clipboard` (`wl-paste --watch`)                                      | **Not ported this pass.** Use `clipmenu`/`greenclip` on X11.                                                                                                                                                                                                                                                                                                          |
| `plugins/background/Background.qml`      | 4    | `WlrLayershell` `WlrLayer.Background` (draws wallpaper on the bg layer)                    | **Drop.** X11 wallpaper = `feh`/`xwallpaper` + picom; keep `scripts/wallpaper-set.sh`.                                                                                                                                                                                                                                                                                |
| `plugins/services/idle/Service.qml`      | 3    | `IdleMonitor`                                                                              | **Drop the `IdleMonitor` source.** No X11 backend. Re-expose the same `idle`/`stay-awake` state file interface driven by `xprintidle` polling + `xset s`, so `indicators/StayAwake.qml` still works.                                                                                                                                                                  |
| `plugins/panels/bluetooth/Panel.qml`     | 3    | `WlrLayershell` overlay; `Quickshell.Bluetooth` (BlueZ/DBus)                               | T1. Data path fine.                                                                                                                                                                                                                                                                                                                                                   |
| `plugins/bar/widgets/Microphone.qml`     | 3    | `Pipewire`                                                                                 | Replace with a `Services/Audio.qml`-backed source widget (same as `panels/audio`).                                                                                                                                                                                                                                                                                    |
| `Ui/PopupCard.qml`                       | 2    | `HyprlandFocusGrab`                                                                        | T2. **Already done locally.**                                                                                                                                                                                                                                                                                                                                         |
| `plugins/services/media/Service.qml`     | 2    | `Quickshell.Hyprland` (window-title enrichment only)                                       | Strip the Hyprland enrichment; MPRIS (`Mpris` service) is desktop-agnostic. Add an MPD fallback (`mpc idleloop`) since this machine runs MPD, not just MPRIS players.                                                                                                                                                                                                 |
| `plugins/bar/widgets/ActiveWindow.qml`   | 2    | `ToplevelManager.activeToplevel`                                                           | **Adapt** to `i3-msg -t subscribe '["window"]'` (focused-window title/app_id).                                                                                                                                                                                                                                                                                        |
| `plugins/bar/widgets/Workspaces.qml`     | 1    | `Quickshell.Hyprland`                                                                      | T3 → `Quickshell.I3`. **Already done locally** (`Bar/widgets/Workspaces.qml`).                                                                                                                                                                                                                                                                                        |
| `plugins/bar/widgets/KeyboardLayout.qml` | 1    | `Hyprland` `activelayout` event + `dispatch("switchxkblayout")`                            | **Adapt.** Poll `scripts/keyboard.sh` (xprop + ctypes `XkbGetState`); click cycles via `xkb-switch` / `ISO_Next_Group` / `setxkbmap`. **Done** (`omarchy.keyboard-layout`). |

### 2c. Not portable / explicitly dropped

`lock` (`WlSessionLock`), `idle` `IdleMonitor` source, `clipboard` (`wl-clipboard`),
`background` (`WlrLayer.Background`), `emojis`, `menu`, `notifications`, `image-picker`,
`dev-gallery`, `panels/audio` PipeWire internals, `bar/widgets/Microphone` PipeWire internals,
`bar` drag-ghost overlays, `AppLibrary` launch-feedback. QS 0.3.0 local build has **no**
`Quickshell.Services.Pipewire` compiled in and **no** X11 backend for `IdleMonitor`/`WlSessionLock`/`ToplevelManager`.

---

## 3. Target `marcello/` layout

```
marcello/
├── bin/                              # vendored + adapted omarchy-* CLI (§5)
│   ├── omarchy-theme-set  omarchy-theme-list  omarchy-theme-next  omarchy-theme-menu
│   ├── omarchy-theme-set-templates  omarchy-theme-current  omarchy-theme-bg-*
│   ├── omarchy-bar  omarchy-cmd  omarchy-launch-shell  omarchy-restart-shell
│   ├── omarchy-audio-*  omarchy-bluetooth-*  omarchy-wifi-*  omarchy-menu (rofi-backed)
│   └── omarchy-battery-*  omarchy-brightness-*  …  (only what a plugin/keybind calls)
├── .config/
│   ├── omarchy/
│   │   ├── shell.json                # bar layout + enabled-plugins + per-plugin settings
│   │   ├── themed/                   # user template overrides (usually empty)
│   │   └── plugins/                  # third-party QS plugins (empty for now)
│   ├── quickshell/                   # ← near-mirror of omarchy-quattro/shell/
│   │   ├── shell.qml                 # mirror; delta: X11 monitor/env, no uwsm OMARCHY_PATH assumption
│   │   ├── Commons/                  # mirror; delta: Color.qml re-adds FileView(colors.toml) (§7),
│   │   │                             #   Style.qml drops hyprctl getoption sync
│   │   ├── Ui/                       # mirror; delta: PopupCard T2, KeyboardPanel T1
│   │   ├── services/                 # mirror PluginRegistry/BarWidgetRegistry/AppLibrary (−ToplevelManager)
│   │   └── plugins/
│   │       ├── bar/                  # mirror; Bar.qml T1/T3, widgets adapted per §2b
│   │       ├── panels/{bluetooth,network,power,weather,clock,monitor}/   # T1, ported
│   │       ├── panels/audio/         # layout mirrored, data = Services/Audio.qml (pactl)
│   │       ├── osd/  polkit/  reminders/  agents/  model-usage/          # T1, ported
│   │       ├── services/{battery,media,nightlight,tmux}/                 # ported
│   │       ├── services/idle/        # ported, IdleMonitor → xprintidle poll
│   │       └── (lock, background, clipboard, emojis, menu, notifications, image-picker  ── absent)
│   └── i3/
│       ├── config.d/02_keybindings.conf   # rewritten to omarchy scheme (§9)
│       ├── config.d/01_theme.conf         # generated by omarchy-theme-set (i3 client.* colors)
│       ├── themes/                        # ← was default/ (one theme); now:
│       │   ├── <name>/colors.toml         # copied verbatim from omarchy-quattro/themes/<name>/
│       │   ├── <name>/backgrounds/
│       │   └── templates/                 # i3.conf.tpl polybar.ini.tpl colors.rasi.tpl
│       │                                  #   dunstrc.tpl picom.conf.tpl  (NEW — omarchy has none)
│       ├── polybar/…                      # colors.ini generated per theme; modules trimmed (§8)
│       └── scripts/                       # i3_quickshell_toggle → `omarchy bar`/`qs ipc` wrappers
└── .local/state/omarchy/                  # runtime: current/theme symlink, toggles/, agents/usage/, …
```

Deployment stays stow/copy. `~/.local/state/omarchy/` is created at first
`omarchy-theme-set` run.

### Upstream-tracking workflow

1. `omarchy-quattro/` is updated wholesale from the GitHub repo (as today).
2. `diff -ru omarchy-quattro/shell marcello/.local/share/omarchy/shell` shows the delta.
3. Each delta must be one of: (a) a §2b transform, (b) a Commons/Style theming
   change from §7, or (c) listed in [`deltas.md`](deltas.md) (the
   canonical list of intentional divergences, kept in sync).
4. On upstream bump: re-apply the tree, then re-apply deltas from `deltas.md`.

---

## 4. Quickshell host mirror (`shell.qml` + registries)

`PluginRegistry.qml`, `BarWidgetRegistry.qml`, `AppSearch.js` — **pure QML/JS +
`FileView`, zero Wayland**. Mirror verbatim.

`shell.qml` deltas:
- `omarchyPath`: **`OMARCHY_PATH=$HOME/.local/share/omarchy`** — a mirror of the
  `omarchy-quattro/` repo root (see [phase-1.md](phase-1.md) topology table), with
  the shell at `$OMARCHY_PATH/shell`. Upstream reads it from the uwsm session env;
  on i3 there is no uwsm, so `i3_autostart` exports it (and prepends
  `$OMARCHY_PATH/bin` to `PATH`) before anything omarchy runs. `~/.local/share/omarchy/shell`
  folds into `$OMARCHY_PATH/shell` (symlink for back-compat, or dropped).
- `defaultsPath`: upstream `OMARCHY_PATH/config/omarchy/shell.json`. Ours ships a
  bundled default at `$OMARCHY_PATH/../omarchy/shell.json` or inline `builtinShellConfig`
  (already present in upstream `shell.qml`) — keep the inline fallback authoritative.
- Screen enumeration: upstream leans on Hyprland monitor names for per-monitor bar
  instances. Use `Quickshell.screens` (X11 RandR names). The `Variants { model:
  Quickshell.screens }` pattern in `Bar.qml` already does this; only
  `Hyprland.focusedMonitor` needs T3.

`omarchy-launch-shell` (vendored, adapted):
- `systemd-cat -t omarchy-shell` → `logger -t omarchy-shell` (Devuan, no systemd) or plain redirect to `~/.local/state/omarchy/shell.log`.
- `hyprctl -j monitors` liveness check → `i3-msg -t get_version` or `xrandr --listmonitors`.
- Keep `QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 quickshell -n -p "$OMARCHY_PATH"`.
- i3 autostart: replace the current `scripts/i3_bar`/`i3_quickshell_toggle` QS launch
  with `exec_always --no-startup-id ~/.config/i3/scripts/omarchy-shell-start` →
  `pgrep -f 'quickshell.*quickshell' || omarchy-launch-shell`.

`shell.json` (interim, polybar visible):
```json
{
  "version": 1,
  "bar": { "enabled": false },
  "plugins": {
    "omarchy.osd": { "enabled": true },
    "omarchy.polkit": { "enabled": true },
    "omarchy.panel.bluetooth": { "enabled": true },
    "omarchy.panel.network": { "enabled": true },
    "omarchy.panel.power": { "enabled": true },
    "omarchy.panel.weather": { "enabled": true },
    "omarchy.panel.clock": { "enabled": true },
    "omarchy.reminders": { "enabled": false }
  },
  "idle": { "screensaver": 150, "lock": 300 }
}
```
Panels are summoned by keybind via `qs ipc call <plugin.id> toggle` (§9 system controls).

---

## 5. Vendored `bin/omarchy-*` (adapted)

Only scripts a plugin or keybinding actually invokes. Adaptation rules:
`pacman`/`yay`/`checkupdates` → `apt`/`apt list --upgradable`; `hyprctl` → `i3-msg`/`xrandr`;
`loginctl`/`systemctl` → `loginctl` (elogind) / `sv`/`service`; `wl-copy`/`wl-paste` → `xclip`/`xsel`;
`grim`/`slurp`/`wl-screenrec` → `maim`/`slop`/`ffmpeg`; `brightnessctl` ok; `pactl` ok; `playerctl` ok;
`walker`/`wofi`/`fuzzel` → `rofi`; `systemd-cat` → `logger`.

| Script                                                        | Purpose                                                                                  | Adaptation                                                                                                                                                                                                                                                                                                                                                             |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `omarchy-theme-set`                                           | swap `current/theme` symlink, restage theme files, re-template, reload apps              | drop `hyprctl reload`; add `i3-msg reload`, `polybar-msg cmd restart` (or relaunch), `dunstctl reload`/SIGUSR, `killall -SIGUSR1 picom` (or restart), re-`sed` app templates. Keep the git-repo-theme deny-list logic.                                                                                                                                                 |
| `omarchy-theme-set-templates`                                 | `sed`-render `default/themed/*.tpl` from `colors.toml` (+ `mix_color`, gradient helpers) | **vendored verbatim** (Phase 1 — pure bash/awk/sed). Our X11 templates go in `~/.config/omarchy/themed/`: `i3.conf.tpl`, `polybar.ini.tpl`, `colors.rasi.tpl` (include-consumers). dunst/picom/GTK are patched **in place** by `omarchy-theme-set`, not templated. `hyprland_active_border` needs no handling — `resolve_theme_ref` falls back to `accent` on its own. |
| `omarchy-theme-list` / `-current` / `-next` / `-dir`          | enumerate/report/cycle themes                                                            | portable as-is (filesystem only).                                                                                                                                                                                                                                                                                                                                      |
| `omarchy-theme-menu` (`omarchy-theme-switcher`)               | picker UI                                                                                | reimplement over `rofi -dmenu` with `preview.png` icons; on select → `omarchy-theme-set "$name"`.                                                                                                                                                                                                                                                                      |
| `omarchy-theme-bg-*`                                          | wallpaper cache/next/set from `current/theme/backgrounds/`                               | swap `swaybg`/`hyprpaper` → `xwallpaper --zoom` / `feh --bg-fill`. Keep `scripts/wallpaper-set.sh`.                                                                                                                                                                                                                                                                    |
| `omarchy-bar`                                                 | `omarchy bar position/transparent/move/set` → edits `shell.json`                         | portable (JSON edit + `qs ipc call omarchy.bar reloadConfig`).                                                                                                                                                                                                                                                                                                         |
| `omarchy-cmd` / `omarchy-cmd-missing` / `omarchy-pkg-missing` | dispatcher + capability probes used by plugins                                           | keep dispatcher; probes swap `pacman -Qi` → `dpkg -s`.                                                                                                                                                                                                                                                                                                                 |
| `omarchy-audio-*`                                             | sink/source switch, volume, mute                                                         | already `pactl`-based upstream — keep.                                                                                                                                                                                                                                                                                                                                 |
| `omarchy-bluetooth-*` / `omarchy-wifi-*`                      | BlueZ / `nmcli` wrappers used by panels                                                  | portable (`bluetoothctl` / `nmcli`).                                                                                                                                                                                                                                                                                                                                   |
| `omarchy-battery-*` / `omarchy-brightness-*`                  | UPower / backlight                                                                       | `upower` + `brightnessctl`/`light` — portable.                                                                                                                                                                                                                                                                                                                         |
| ~~`omarchy-agent-usage-*`~~                                   | AI usage collectors                                                                      | **not vendored** (decision 7).                                                                                                                                                                                                                                                                                                                                         |
| `omarchy-restart-shell`                                       | `pkill quickshell; omarchy-launch-shell`                                                 | trivial.                                                                                                                                                                                                                                                                                                                                                               |
| `omarchy-menu`                                                | structured command palette                                                               | thin `rofi` script (decision 4 keeps rofi); wire `Super+Space`.                                                                                                                                                                                                                                                                                                        |

Everything else in `bin/` (gaming, webapp, install, snapshot, plymouth, gnome,
obsidian, fingerprint, `omarchy-agent-*` collectors beyond usage JSON) is **not
vendored**. Add on demand.

---

## 6. Bar widgets — mapping

Omarchy widget id ↔ current `marcello` widget ↔ action. "Ported" = mirror
upstream file + §2b transform. "Local" = a `marcello`-authored widget with no
upstream file — keep, register it in `BarWidgetRegistry` the same way upstream
registers 1p widgets, list it in `deltas.md`.

| omarchy id                | upstream file                                                                                             | marcello now                                                                                                     | Action                                                                                                                                                                                                                                                                                                                                               |
| ------------------------- | --------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `omarchy.menu`            | `Ui/BarIconButton`                                                                                        | `Bar/widgets/MenuButton.qml`                                                                                     | Ported (icon button → `omarchy-menu`).                                                                                                                                                                                                                                                                                                               |
| `omarchy.workspaces`      | `bar/widgets/Workspaces.qml`                                                                              | `Bar/widgets/Workspaces.qml` (I3)                                                                                | **Done** — reconcile with upstream, keep I3.                                                                                                                                                                                                                                                                                                         |
| `omarchy.clock`           | `bar/widgets/Clock.qml`                                                                                   | `Bar/widgets/Clock.qml`                                                                                          | Ported. Right-click → `panels/clock` (calendar).                                                                                                                                                                                                                                                                                                     |
| `omarchy.tray`            | `bar/widgets/Tray.qml` + `TrayModel.js`                                                                   | `Bar/widgets/Tray.qml`                                                                                           | Ported (SNI/DBus). Needs `//@ pragma UseQApplication` (already in local `shell.qml`).                                                                                                                                                                                                                                                                |
| `omarchy.spacer`          | `bar/widgets/Spacer.qml`                                                                                  | `Bar/widgets/Separator.qml`                                                                                      | Ported (rename to `Spacer` to match).                                                                                                                                                                                                                                                                                                                |
| `omarchy.system-update`   | `bar/widgets/SystemUpdate.qml`                                                                            | `Bar/widgets/Updates.qml`                                                                                        | Adapt: backing check → `apt list --upgradable` via `omarchy-cmd`. Keep upstream IpcHandler shape.                                                                                                                                                                                                                                                    |
| `omarchy.keyboard-layout` | `bar/widgets/KeyboardLayout.qml`                                                                          | `plugins/bar/widgets/KeyboardLayout.qml`                                                                         | **Done** — poll `keyboard.sh`; click → `keyboard.sh next`. |
| `omarchy.active-window`   | `bar/widgets/ActiveWindow.qml`                                                                            | —                                                                                                                | **Excluded for now** (2026-09-01, not rejected) — see `deltas.md`'s "Not ported" list. Adaptation path if revisited: `i3-msg -t subscribe '["window"]'`.                                                                                                                                                                                             |
| `omarchy.indicators`      | `bar/widgets/Indicators.qml` + `indicators/*`                                                             | `Bar/widgets/Notifications.qml` (partial)                                                                        | Port container + `Dnd`, `StayAwake`, `NightLight`, `ScreenRecording`, `Reminder`, `TmuxAlert`. Drop `Dictation` (Wayland `wtype`/voxinput).                                                                                                                                                                                                          |
| `omarchy.microphone`      | `bar/widgets/Microphone.qml`                                                                              | `Bar/widgets/Volume.qml` (output, pactl)                                                                         | Rebuild mic widget on `Services/Audio.qml` source side. Keep `Volume.qml` as the output widget (local).                                                                                                                                                                                                                                              |
| ~~`omarchy.agents`~~      | `plugins/agents/Panel.qml`                                                                                | —                                                                                                                | **Not ported** (decision 7).                                                                                                                                                                                                                                                                                                                         |
| `omarchy.audio`           | `plugins/panels/audio/Panel.qml`                                                                          | `Bar/widgets/Volume.qml`                                                                                         | Panel layout ported, data = `Services/Audio.qml`.                                                                                                                                                                                                                                                                                                    |
| — (no upstream)           | —                                                                                                         | `Bar/widgets/SysStats.qml`                                                                                       | **Local — keep as 3 readouts** (`cpu`/`gpu`/`memory`). `plugins/panels/monitor` **not** ported (decision 6). `scripts/gpu.sh` (`radeontop`) unchanged.                                                                                                                                                                                               |
| —                         | —                                                                                                         | `Bar/widgets/Battery.qml`                                                                                        | Local — keep. (Upstream shows battery inside `panels/power`.)                                                                                                                                                                                                                                                                                        |
| —                         | —                                                                                                         | `Bar/widgets/Bluetooth.qml` `Network.qml` `Vpn.qml` `Timer.qml` `Mpd.qml` `WallpaperButton.qml` `HelpButton.qml` | Local bar widgets. Keep; back each with the ported `panels/*` where one exists (bluetooth, network), keep `Vpn`/`Timer`/`Mpd`/`Help` as pure-local (no upstream equivalent).                                                                                                                                                                         |
| `omarchy.weather`         | `plugins/panels/weather/{BarWidget,Panel,Model.js,status.sh,manifest.json}`                               | `Bar/widgets/Weather.qml`                                                                                        | **Decision (2026-08-30): drop the local widget, adopt upstream.** Needs the plugin host (`BarWidget` base + `settings`/popout coordination — Phase 3), `Panel.qml` T1 (Phase 5), the real `plugins/bar` engine (Phase 8), and vendored `omarchy-weather-{icon,status}` + `omarchy-notification-send`. Until then `Weather.qml` stays as the interim. |
| `omarchy.power`           | `plugins/panels/power/{Panel,Model.js,manifest.json}` (panel only — upstream has **no** bar power widget) | `Bar/widgets/PowerButton.qml`                                                                                    | **Decision (2026-08-30): drop the local widget, adopt upstream.** Upstream summons the power panel by hotkey (`Super+Escape`, §9b) not a bar button. Port `Panel.qml` with T1 (Phase 5); wire `Super+Escape` → `qs ipc call omarchy.power toggle`. `PowerButton.qml` stays as the interim until then.                                                |
| `omarchy.media`           | `plugins/services/media/Service.qml`                                                                      | `Bar/widgets/Mpd.qml`                                                                                            | Port MPRIS service (−Hyprland enrichment); keep MPD `mpc idleloop` fallback as `Mpd.qml`'s source.                                                                                                                                                                                                                                                   |

Final bar `shell.json` layout (when the QS bar goes live, post-polybar):
```
left:   omarchy.menu, omarchy.spacer(12), omarchy.workspaces
center: omarchy.media, omarchy.clock
right:  omarchy.system-update, omarchy.weather, SysStats:cpu, SysStats:gpu, SysStats:mem,
        omarchy.keyboard-layout, omarchy.audio, bluetooth(local), network(local), vpn(local),
        omarchy.indicators, omarchy.tray, battery(local)
        (power: no bar widget — summoned by Super+Escape → omarchy.power panel)
```

---

## 7. Theming

### Mechanism (adopted from upstream, verbatim where possible)

1. `omarchy-theme-set "<Name>"` points `~/.local/state/omarchy/current/theme` →
   `~/.config/i3/themes/<name>/` (which holds the verbatim upstream `colors.toml`
   + `backgrounds/`).
2. **Quickshell reloads live.** `Commons/Color.qml` re-adds upstream's
   `FileView { path: currentThemePath + "/colors.toml" }` +
   `FileView { path: ~/.config/omarchy/shell.toml }` (the two the current local
   `Color.qml` deleted for single-theme). Reassigning `shellValues`/palette on
   `onFileChanged` re-evaluates every surface binding. **No restart.**
3. **Everything else is re-templated + reloaded** by `omarchy-theme-set`:
   `omarchy-theme-set-templates` renders `default/themed/*.tpl` **plus our new
   templates** into the theme dir / target configs, then the script runs
   `i3-msg reload`, polybar restart, `dunstctl reload`, picom restart.

### `colors.toml` schema (all 22 themes, verified uniform)

```
mode = "dark" | "light"
accent  selection  muted
background  dark_background  darker_background  lighter_background
foreground  dark_foreground  light_foreground  bright_foreground
red yellow orange green cyan blue magenta brown
bright_red bright_yellow bright_green bright_cyan bright_blue bright_magenta
```
This is a **strict superset** of the current `themes/default/theme.bash`
(16 ANSI + bg/fg/accent). Drop `theme.bash`; `colors.toml` is ground truth.

### `Commons/Color.qml` — the surface ramp gap

Upstream derives per-surface roles from `shell.toml` (generated from
`shell.toml.tpl`). Its `[hyprland] active-border` uses a `hyprland_active_border`
gradient var we don't define — **no action needed**: `omarchy-theme-set-templates`'s
`resolve_theme_ref` falls back to the second arg (`accent`) automatically.
Verified in Phase 1 against `tokyo-night`/`gruvbox`/`catppuccin-latte`.

`colors.toml` has no `surface0/1/2` ramp (the local `Color.qml` and old
`eww.scss` used one for `.ws-btn` states). Derive it in `Color.qml`:
`selection` / `muted` / `lighter_background` / `dark_background` for the 3-4
steps, or `Util`-mix `background`→`foreground` at 4/8/12%. Encapsulate so
widgets are unchanged.

### New templates to author (`themes/templates/` — omarchy ships none of these)

| Template                                      | Renders                                                                            | From tokens                                                                       |
| --------------------------------------------- | ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `i3.conf.tpl` → `config.d/01_theme.conf`      | `client.focused` / `.focused_inactive` / `.unfocused` / `.urgent` / `.placeholder` | `accent`, `background`, `dark_background`, `foreground`, `dark_foreground`, `red` |
| `polybar.ini.tpl` → `polybar/colors.ini`      | `BACKGROUND FOREGROUND ALT* ACCENT` + 16 ANSI                                      | direct map; ANSI = `red…bright_magenta`                                           |
| `colors.rasi.tpl` → `rofi/shared/colors.rasi` | rofi `*` block                                                                     | `background`, `foreground`, `accent`, `selection`, `urgent`=`red`                 |
| `dunstrc.tpl` → dunst colors                  | `[urgency_low/normal/critical]` fg/bg/frame                                        | `background`, `foreground`, `dark_background`, `red`                              |
| `picom.conf.tpl` → picom                      | `shadow-color`, inactive/active opacity, corner tint                               | `mode`-aware: dark → `#000000` shadow; light → `#3b3b3b`, lower `shadow-opacity`  |
| GTK (see below)                               | icon theme + light/dark variant only                                               | `themes/<name>/icons.theme`, `colors.toml` `mode`                                 |

Existing `themes/apply.sh` logic (`apply_polybar`, `apply_rofi`, `apply_dunst`,
`apply_compositor`, `apply_i3wm`, `apply_terminal`, `apply_appearance`) is the
starting point — convert each `apply_*` function into a `.tpl` + a call from
`omarchy-theme-set`. Replace `pastel` (derived colors) with the `mix_color`
awk function already in `omarchy-theme-set-templates`.

### `mode = "light"` — first-class this time

The current stack has only rendered one dark theme. Light themes
(`catppuccin-latte`, `flexoki-light`, `white`) need a real look-test pass:
picom `shadow-color`/opacity, i3 border contrast, rofi selection contrast,
dunst frame, polybar `ALTBACKGROUND` derivation direction (lighten vs darken —
`apply.sh` currently hardcodes `pastel lighten`; must flip on `mode`).

### App color templates from `default/themed/` (decision 5 — WM chrome + terminals + GTK)

**Render:** `alacritty.toml.tpl`, `kitty.conf.tpl` (the terminals in use) — into the
same targets `apply.sh` writes today.

**GTK — chosen: Option A (icon + variant only).** `omarchy-theme-set` keeps one
permanently-installed GTK theme (the `Catppuccin-Macchiato` GTK theme already
shipped in `marcello/.local/share/themes/`, or swap to `Orchis-Dark`/`-Light`);
on each switch it only rewrites `gtk-icon-theme-name` from
`themes/<name>/icons.theme` and flips the theme's light/dark variant when
`colors.toml` `mode` changes. This is what Omarchy itself does — Omarchy ships
one GTK look and varies only the icon theme + `prefer-dark` per theme; it never
recolors GTK to each palette. Reuse `apply.sh::apply_appearance`'s
`xsettingsd`/`.gtkrc-2.0`/`gtk-3.0`/`gtk-4.0` sed logic; just drive
`icon_theme`/`gtk_theme` from the new sources instead of `theme.bash`.
GTK apps end up dark-on-dark / light-on-light and never clash, at zero
per-theme maintenance cost.

*Rejected:* **Option B** (generate `gtk.css` `@define-color` overrides from
`colors.toml`) — only reaches libadwaita/Adwaita-named-color apps, GTK3 apps
with their own CSS ignore it, GTK3≠GTK4, restarts needed → partial, inconsistent
coverage for a handful of GTK apps. **Option C** (build a full GTK3/4 theme dir
per switch, à la Gradience) — best fidelity but a real sub-project, slow switch,
brittle across GTK releases; overkill for thunar + a few dialogs. Revisit B
later only if GTK apps visibly clash.

**Wired but commented out of the render list** (flip on if wanted, `.tpl` is cheap):
`btop.theme.tpl`, `chromium.theme.tpl`.

**Skip** (editors — decision 5): `neovim.lua.tpl`, `vscode-theme.json.tpl`,
`helix.toml.tpl`, `obsidian.css.tpl`. Editor themes stay whatever they are;
set them once by hand.

**Skip** (not applicable to this stack): `hyprland.lua.tpl`, `gum_env.lua.tpl`,
`keyboard.rgb.tpl`, `hyprland-preview-share-picker.css.tpl`, `foot.ini.tpl`,
`ghostty.conf.tpl`, `pi.json.tpl`, `claude.json.tpl`.

---

## 8. polybar interim — module trim

Keep polybar visible; QS host provides panels/OSD/polkit/agents. Comment out
polybar modules with **no** Omarchy widget behind them so the interim bar
matches the eventual QS bar's capability set.

Current `modules-right`:
`timer sep weather space wallpapers space cpu gpu memory space keyboard space volume space bluetooth space network vpn minspace updates space help space notifications space date sep battery space sysmenu`

| polybar module       | Omarchy widget?                                     | Interim action                                                                           |
| -------------------- | --------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `menu`               | `omarchy.menu`                                      | keep                                                                                     |
| `i3`                 | `omarchy.workspaces`                                | keep                                                                                     |
| `tray`               | `omarchy.tray`                                      | keep                                                                                     |
| `mpd`                | `omarchy.media` (MPRIS; MPD via fallback)           | keep                                                                                     |
| `weather`            | local `Weather` + `panels/weather`                  | keep                                                                                     |
| `cpu` `gpu` `memory` | local `SysStats` (3 readouts)                       | keep all three (decision 6 — no `panels/monitor`)                                        |
| `keyboard`           | `omarchy.keyboard-layout`                           | keep                                                                                     |
| `volume`             | `omarchy.audio`                                     | keep                                                                                     |
| `bluetooth`          | `panels/bluetooth`                                  | keep                                                                                     |
| `network`            | `panels/network`                                    | keep                                                                                     |
| `updates`            | `omarchy.system-update`                             | keep                                                                                     |
| `date`               | `omarchy.clock`                                     | keep                                                                                     |
| `battery`            | local `Battery` / `panels/power`                    | keep                                                                                     |
| `sysmenu`            | `omarchy.power`                                     | keep                                                                                     |
| `notifications`      | — (dunst stays, decision 4)                         | **keep** (thin `dunstctl` button — still no *widget*, but it's the sanctioned exception) |
| **`timer`**          | — none                                              | **comment out**                                                                          |
| **`vpn`**            | — none (only `panels/tailscale`, different)         | **comment out**                                                                          |
| **`help`**           | — none (omarchy uses `Super+K`/menu)                | **comment out**                                                                          |
| **`wallpapers`**     | `background`/`image-picker` are Wayland, not ported | **comment out** (wallpaper still cycles via `omarchy-theme-bg-next` keybind)             |

Result:
```
modules-left   = menu minspace i3 sep tray
modules-center = mpd
modules-right  = weather space cpu gpu memory space keyboard space volume space bluetooth space network space updates space notifications space date sep battery space sysmenu
```
`[module/timer] [module/vpn] [module/help] [module/wallpapers]` definitions
stay in `modules.ini` (commented out of the layout only), for rollback.

---

## 9. Keybindings — marcello (Archcraft) vs Omarchy

Source: `marcello/.config/i3/config.d/{02_keybindings,03_mousebindings,04_modes}.conf`
vs `omarchy-quattro/manual/07-hotkeys.md`. `$MOD = Mod4 (Super)`, `$ALT = Mod1`.

### 9a. Semantic conflicts (same chord, different meaning — must be resolved)

| Chord                                 | marcello now                                        | Omarchy                                     | Resolution                                                                                                                                                           |
| ------------------------------------- | --------------------------------------------------- | ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Super+Tab`                           | `focus next` (container)                            | next workspace                              | → **`workspace next`** (Omarchy). Container cycling moves to `Alt+Tab`.                                                                                              |
| `Super+W`                             | launch browser                                      | close window                                | → **`kill`** (Omarchy). Browser → `Super+Shift+Return`.                                                                                                              |
| `Super+C`                             | `kill`                                              | copy (universal clipboard)                  | → keep **`kill`** on `Super+C` **and** add `Super+Q`/`Super+W` = kill. **Do not** adopt universal clipboard (X11 global Ctrl+C rebind is fragile) — documented skip. |
| `Super+X`                             | powermenu (QS)                                      | cut                                         | → **`Super+Escape`** = system/power menu (Omarchy). `Super+X` unbound.                                                                                               |
| `Super+T`                             | `layout tabbed` (via `Super+Shift+t`) / unused bare | toggle tiling/floating                      | → **`floating toggle`** (Omarchy). Was `Super+M`.                                                                                                                    |
| `Super+S` / `Super+Shift+S`           | `layout stacking`                                   | scratchpad show / move-to-scratchpad        | → **`scratchpad show`** / **`move scratchpad`** (Omarchy). Stacking layout → `Super+Shift+S` dropped (rarely used).                                                  |
| `Super+L`                             | launcher toggle (QS)                                | toggle dwindle/scrolling layout (n/a in i3) | → launcher moves to **`Super+Space`** (Omarchy menu) / **`Super+Alt+Space`** (apps). `Super+L` unbound (no i3 analogue).                                             |
| `Super+M`                             | `floating toggle`                                   | (bare unused; `Super+Shift+M` = music)      | → `Super+M` freed; music on **`Super+Shift+M`**.                                                                                                                     |
| `Super+N`                             | rofi network menu                                   | (bare unused; `Super+Shift+N` = editor)     | → network panel to **`Super+Ctrl+W`** (Omarchy). Editor on `Super+Shift+N`.                                                                                          |
| `Super+B`                             | `workspace back_and_forth`                          | (bare unused; `Super+Ctrl+B` = bluetooth)   | → keep `back_and_forth` on **`Super+Ctrl+Tab`** (Omarchy "former workspace"). Bluetooth panel on `Super+Ctrl+B`.                                                     |
| `Super+H` / `Super+V`                 | `split horizontal` / `split vertical`               | — (`Super+J` = toggle h/v split in Omarchy) | → **`Super+J`** = `split toggle`. Keep `Super+H`/`Super+V` as explicit split (i3 extra, no conflict).                                                                |
| `Super+P`                             | color picker (`--release`)                          | toggle pseudo layout (n/a)                  | keep color picker (no conflict; Omarchy's is layout-only).                                                                                                           |
| `Super+F`                             | `fullscreen toggle`                                 | fullscreen                                  | **same** ✅                                                                                                                                                           |
| `Super+Return`                        | terminal                                            | terminal                                    | **same** ✅                                                                                                                                                           |
| `Super+Shift+F`                       | file manager                                        | file manager                                | **same** ✅                                                                                                                                                           |
| `Super+arrows` / `Super+Shift+arrows` | focus / move                                        | focus / swap                                | **same** ✅ (`move` ≈ swap in i3)                                                                                                                                     |
| `Super+1..0` / `Super+Shift+1..0`     | ws switch / move+follow                             | ws switch / move                            | **same** ✅ (Omarchy 1-4 only; keep 1-10)                                                                                                                             |

### 9b. Omarchy chords to add (no marcello conflict)

| Chord                                                 | Action                       | i3 implementation                                                                                                                               |
| ----------------------------------------------------- | ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `Super+Space`                                         | Omarchy menu                 | `exec omarchy-menu` (rofi)                                                                                                                      |
| `Super+Alt+Space`                                     | Apps menu                    | `exec rofi -show drun`                                                                                                                          |
| `Super+Escape`                                        | System/power menu            | `exec qs ipc call omarchy.power toggle` (or rofi powermenu)                                                                                     |
| `Super+Ctrl+L`                                        | Lock                         | `exec ~/.config/i3/scripts/i3_lock` (was `Alt+L`)                                                                                               |
| `Super+Q`                                             | Close window                 | `kill`                                                                                                                                          |
| `Ctrl+Alt+Delete`                                     | Close all windows            | `exec i3-msg '[workspace=__focused__] kill'` per-ws script                                                                                      |
| `Super+Ctrl+A`                                        | Audio panel                  | `exec qs ipc call omarchy.audio toggle`                                                                                                         |
| `Super+Ctrl+B`                                        | Bluetooth panel              | `exec qs ipc call omarchy.panel.bluetooth toggle`                                                                                               |
| `Super+Ctrl+W`                                        | Wifi/network panel           | `exec qs ipc call omarchy.panel.network toggle`                                                                                                 |
| `Super+Ctrl+P`                                        | Power panel                  | `exec qs ipc call omarchy.panel.power toggle`                                                                                                   |
| `Super+Ctrl+D`                                        | Display panel                | `exec ~/.config/i3/scripts/i3_display.sh menu` (xrandr)                                                                                         |
| `Super+Ctrl+Alt+D`                                    | Calendar panel               | `exec qs ipc call omarchy.panel.clock toggle`                                                                                                   |
| `Super+Ctrl+1..9`                                     | Toggle bar panel N           | `exec qs ipc call omarchy.bar togglePanelAt right N`                                                                                            |
| `Super+Ctrl+T`                                        | Activity (btop)              | `exec $terminal -e btop` (was `Alt+Ctrl+H`)                                                                                                     |
| `Super+Ctrl+C`                                        | Capture menu                 | `exec ~/.config/i3/scripts/i3_capture menu` (maim/slop)                                                                                         |
| `Super+Alt+Return`                                    | Tmux terminal                | `exec $terminal -e tmux` (was terminal `--full`)                                                                                                |
| `Super+Shift+Return`                                  | Browser                      | `exec $web_browser`                                                                                                                             |
| `Super+Shift+N`                                       | Editor                       | `exec $text_editor` (**Sublime** — not nvim; keep `$text_editor` var. Frees `Super+Shift+E` for Omarchy's email webapp slot, or leave unbound.) |
| `Super+Shift+M`                                       | Music                        | `exec $music_player` (was `Alt+Ctrl+M`)                                                                                                         |
| `Super+Shift+/`                                       | Password manager             | `exec` (user choice; stub)                                                                                                                      |
| `Super+Scroll` (`button4/5`)                          | Workspace cycle              | `bindsym $MOD+button4/5 workspace prev/next`                                                                                                    |
| `Ctrl+Alt+Tab` / `+Shift+Tab`                         | Cycle monitor focus          | `focus output next` / `prev`                                                                                                                    |
| `Alt+Tab` / `Alt+Shift+Tab`                           | Cycle windows on workspace   | `focus next`/`prev` (was `Super+Tab`)                                                                                                           |
| `Super+Shift+Alt+1..4`                                | Move window to ws, no follow | `move container to workspace number N` (no `workspace` after)                                                                                   |
| `Shift+XF86MonBrightnessUp/Down`                      | Max/min brightness           | `exec brightnessctl set 100%` / `1%`                                                                                                            |
| `Alt+XF86MonBrightness*` / `Alt+XF86Audio*`           | 1% steps                     | `exec ... set 1%-`/`+1%`                                                                                                                        |
| `Alt+XF86AudioPlay` / `Alt+Shift+…`                   | Next / prev track            | `exec playerctl next` / `previous`                                                                                                              |
| `Super+Minus` / `Super+Equal` (+`Shift`/`Alt`/`Ctrl`) | Resize edges, step sizes     | `resize shrink/grow width/height {2,10,20} px or … ppt` (replaces `Super+Alt+arrows`)                                                           |

### 9c. Omarchy features i3 cannot do 1:1 (document as gaps, keep marcello's or omit)

| Omarchy                                                                  | Why not                                               | marcello disposition                                          |
| ------------------------------------------------------------------------ | ----------------------------------------------------- | ------------------------------------------------------------- |
| `Super+G` / `Super+Alt+G` / `Super+Alt+Tab` window **grouping**          | i3 has tabbed/stacked containers, not Hyprland groups | map `Super+G` → `layout toggle tabbed split`; drop the rest   |
| `Super+L` dwindle↔scrolling, `Super+P` pseudo, `Super+J` natural/stretch | i3 layout model differs                               | omit                                                          |
| `Super+Home` / `Super+Alt+Home` save/restore window width                | no i3 primitive                                       | omit                                                          |
| `Super+Ctrl+Z` / `Super+Ctrl+Alt+Z` screen zoom                          | no compositor zoom on picom                           | **unbound** (decision)                                        |
| `Super+/` monitor scaling steps                                          | `xrandr --scale` is coarse/janky                      | **unbound**; `i3_display.sh` presets remain on `Super+Ctrl+D` |
| `Super+Ctrl+F` fullscreen inside window                                  | no i3 primitive                                       | omit                                                          |
| `Super+Alt+F` full-width                                                 | no i3 primitive                                       | approximate with `resize` or omit                             |
| Universal clipboard `Super+C/X/V`                                        | X11 global rebind fragile                             | **omit by decision**                                          |
| `CapsLock`-led emoji / XCompose leader                                   | omarchy ships a custom `~/.XCompose` + `xremap`       | out of scope; can add `~/.XCompose` later independently       |
| `Super+Ctrl+V` clipboard manager                                         | wl-clipboard                                          | `clipmenu`/`greenclip` bind if adopted later                  |

### 9d. i3-only bindings with no Omarchy equivalent — **keep**

`Super+Shift+C` reload · `Ctrl+Shift+R` restart · `Super+Shift+Q` exit ·
`Super+Shift+R` → Resize mode · `Super+Shift+G` → gaps mode · `Super+Y` border toggle ·
`Super+A`/`Super+D` focus parent/child · `Super+Shift+Space` focus mode_toggle ·
`Super+Alt+C`/`Super+Alt+P` float move center / to mouse ·
mouse: `button2` kill on titlebar, `Super+button2` kill whole-window,
`floating_modifier $MOD` (drag=LMB, resize=RMB — matches Omarchy `Super+Mouse`).

### 9e. Deliverable

Rewrite `config.d/02_keybindings.conf` from the 9a resolutions + 9b additions +
9d retentions. Ship `rofi/help-keybindings.txt` regenerated from the new map
(`help-bindings.py` parses the i3 config — keep it). `Super+K` (Omarchy's
"show all hotkeys") → bind to `i3_help`.

---

## 10. Phased execution

Each phase is independently runnable; polybar stays visible until Phase 8.

| Phase | Deliverable                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Verify                                                                                                                                                                                                                                    |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0     | Pin QS 0.3.0 build (no apt pkg) — commit build steps/commit hash to `docs/`. **Seed [`deltas.md`](deltas.md)** now from the existing local divergences (`Commons/Color.qml`, `Commons/Style.qml`, `Ui/PopupCard.qml`, `Ui/KeyboardPanel.qml`, `Bar/widgets/Workspaces.qml`, `Bar/widgets/KeyboardLayout.qml`, `shell.qml`).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | `quickshell --version` == `0.3.0 (10b439f…)`; `deltas.md` lists every current divergence with its §2b transform id.                                                                                                                       |
| 1     | **Core built — see [phase-1.md](phase-1.md).** Vendored `omarchy-theme-{color,set-templates,list,current,dir,refresh}` verbatim; adapted `omarchy-theme-set` + `omarchy-restart-{polybar,terminal}`; new `omarchy-theme-{next,menu}`; templates `i3.conf.tpl`/`polybar.ini.tpl`/`colors.rasi.tpl` in `~/.config/omarchy/themed/`. **Remaining:** deploy + a per-theme + light-theme live pass (the repo-side activation edits landed 2026-08-30). The live `~/.local/share/omarchy` tree (`themes/`, `default/`, `bin/`) is a detached `cp -r` of the repo — see phase-1.md "Deployment topology".                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | sandbox render verified for tokyo-night/gruvbox/catppuccin-latte; live `omarchy-theme-set "Gruvbox"` then `"Flexoki Light"` after activation.                                                                                             |
| 2     | **Commons/ + Ui/ mirrored verbatim — see [phase-2.md](phase-2.md).** `Color.qml` = byte-identical upstream (verbatim-mirror decision, 2026-08-30); local flat palette + bar/popup vocabulary moved to `Services/BarPalette.qml`. `Style.qml` drops hyprctl + fc-match. `PopupCard`/`KeyboardPanel` keep local T1/T2. 17 Bar widgets re-pointed at `BarPalette`. `services/` (PluginRegistry/BarWidgetRegistry/AppLibrary) is **Phase 3**, not done here.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | `quickshell -p <repo>` loads clean (done, sandbox). **Remaining:** deploy + eyeball bar/popups; live recolour needs the Phase 3 IPC host.                                                                                                 |
| 3     | **Repo work done 2026-08-31 — see [phase-3.md](phase-3.md).** QS tree moved `marcello/.config/quickshell/` → `marcello/.local/share/omarchy/shell/`. `shell.qml` = upstream mirror − S1–S5 (pragma; local `Bar/` loader replaces `plugins/bar`; drop `Style.scheduleRefresh`; drop `appLibrary`; path comments). `services/{PluginRegistry,BarWidgetRegistry}` verbatim. `omarchy-launch-shell` adapted (logfile + `i3-msg` liveness), `omarchy-restart-shell` rewritten, `omarchy-shell` vendored (X11 DISPLAY recovery). `shell.json` + `i3_bar`/`i3_quickshell_toggle` rewired. AppLibrary deferred (S4).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | `quickshell -p <repo>` loads clean (done). **Live:** `omarchy-shell shell ping` → `ok`, popups still work, `omarchy-theme-set` recolours QS live.                                                                                         |
| 4     | **Repo work done 2026-08-31 — see [phase-4.md](phase-4.md).** `plugins/osd/` ported (T1: overlay `PanelWindow` → `aboveWindows`/`focusable:false`; first-party auto-enabled, `keepLoaded`). `plugins/polkit/` ported (T1: `focusable` + `focus-polkit.py` XSetInputFocus nudge) but **disabled by default** (`disabledPlugins`) — clashes with the session's `mate-polkit`; opt-in documented. `i3_volume`/`i3_brightness` → `omarchy-shell osd show` (dunst fallback).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | `quickshell -p <repo>` loads (one incubation-race WARN to check live). **Live:** `omarchy-shell osd show …` draws the overlay; Fn keys show it; polkit only after opt-in.                                                                 |
| 5     | **bluetooth · network · power done 2026-08-31 — see [phase-5.md](phase-5.md).** `omarchy.bluetooth` (drop Pipewire audio-routing; `omarchy-bluetooth-{device,power}` vendored), `omarchy.network` (`wl-copy`→`xclip`; `omarchy-network-*` + softened `omarchy-dns` vendored), `omarchy.power` (battery panel; `omarchy-battery-*`/`omarchy-powerprofiles-*` vendored). All swapped into the bar layout for their `omaxian.*` widgets + rebound `Super+Ctrl+{B,W,P}`. **`omarchy.weather` done 2026-08-31** — `plugins/panels/weather/` + `omarchy-weather-{status,location,icon}`/`omarchy-notification-{weather,send}` mirrored verbatim (all X11-safe: curl/wttr.in/open-meteo, `busctl`→dunst); `local.weather` → `omarchy.weather` in the layout. **`omarchy.audio` done 2026-08-31** — full panel on a `pactl` backend: `Services/Audio.qml` gained a Pipewire-`nodes`-shaped graph API (`pactl -f json list` + `pactl subscribe`), `plugins/panels/audio/` adapted from upstream (Pipewire/Mpris/PwObjectTracker/PwNodePeakMonitor out; VU meter + MPRIS labels dropped); `omarchy-audio-*` scripts vendored; `local.volume` → `omarchy.audio`. **clock n/a** (`omarchy.clock` bar widget already in the bar since Phase 8). | `quickshell -p <repo>` clean ✓; deployed, IPC-toggles ✓, `omarchy-network-status`/`omarchy-weather-status` → real data; audio panel renders sinks/sources + sliders. **Live:** open each panel, connect/disconnect + device-switch works. |
| 6     | **Tractable slice done 2026-08-31 — see [phase-6.md](phase-6.md).** `Indicators` default list → `["NightLight", "Dnd", "StayAwake"]` (dropped `Dictation`/`Reminder`/`ScreenRecording`). `Dnd` → `dunstctl is-paused` / `set-paused` (decision 4). `plugins/services/nightlight` → `redshift` one-shot + `~/.local/state/omarchy/nightlight.temp` state file; `omarchy-toggle-nightlight` vendored. `plugins/services/idle` → 360→~70 lines: idle-lock automation **dropped** (manual lock only), kept the `StayAwake` toggle → `xset s`/DPMS + `stay-awake` state file. IPC verified: `nightlight status`→`{"enabled":false,"temperature":6500}`, `idle status`→`{"stayAwake":false}`, `idle toggle` on/off ✓, log clean. **Deferred:** `media` (836 lines, Pipewire), `battery` service (power panel already reads battery), `tmux`/`Reminder`/`ScreenRecording` indicators, full idle→lock automation.                                                                                                                                                                                                                                                                                                                        | **Live:** bar shows the 3 glyphs; click `Dnd` (dunst pauses), `NightLight` (screen warms), `StayAwake` (`xset q` shows s/DPMS off).                                                                                                       |
| 7     | **Done 2026-08-31 — see [phase-7.md](phase-7.md).** `02_keybindings.conf` rewritten to §9 (114 binds); `03_mousebindings` +Super-scroll; `04_modes` drops the Move-mode trigger; `help-keybindings.txt` regenerated; `i3_help` de-staled; polybar `modules-right` trimmed to §8 (no timer/help). Deviations: the `Super+Space` family is remapped (xkb `grp:win_space_toggle` eats it) — launcher stays `Super+L`, apps `Super+Alt+L`; system panels are interim rofi/scripts until Phase 8.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | `i3 -C` validates clean (done). **Live:** `i3-msg reload`, spot-check §9b chords, `Super+K` help.                                                                                                                                         |
| 8     | **Stages 1–6 done 2026-08-31 — see [phase-8.md](phase-8.md).** (1) strut spike **passed** (i3 honours `_NET_WM_STRUT_PARTIAL` from a QS X11 `PanelWindow` under glx-picom). (2) clean widget/indicator files mirrored. (3) `Bar.qml` T1 (`WlrLayershell`→`aboveWindows`) + T3 (`Hyprland`→`I3.focusedMonitor`) + **drag-ghost/move-ghost overlays deleted**. (4) `Workspaces` T3'd; `KeyboardLayout` = local X11 poll; `Dictation` dropped from `Indicators`; `ActiveWindow`/`Microphone`/`SystemUpdate` deferred. (5) `shell.qml` S2 walked back — real `plugins/bar` = `shell.bar`, local flat `Bar/` kept as an invisible popup host (`LocalHost`). (6) `shell.json` `bar.enabled:true` + minimal layout (`workspaces`\|`clock`\|`keyboard-layout,indicators,tray`). **Deployed + live 2026-08-31:** `listPlugins` shows `omarchy.bar` + widgets enabled; real bar window emits `_NET_WM_STRUT_PARTIAL 0,0,26,0`, i3 ws rect `y:41→67`. (7) `i3_bar` polybar launch commented out (repo); picom needs no change (`window_type='dock'` already excluded).                                                                                                                                                                      | ✓ live; deploy `i3_bar` + `i3-msg reload` → single QS bar.                                                                                                                                                                                |
| 9     | **DONE — 2026-08-31.** New `Ui/CenteredModal.qml` (content-sized card centred on screen via a 1px full-width `PanelWindow` strip + a `PopupWindow`) replaces the full-screen `WlrLayershell` overlays that picom v12.5 glx blacks out. On it: **`wifiqr`** (`Model.js`/`manifest` verbatim), **`speedtest`** + **`disk-speedtest`** (`Panel.qml` verbatim; `Ui/SpeedTestOverlay.qml` re-rooted on `CenteredModal`, `SpeedDial` gauge verbatim; `omarchy-{network,disk}-speedtest` + `omarchy-cmd-present` vendored). **`reminders`** Devuan-ported earlier (detached `setsid` sleepers + `$XDG_RUNTIME_DIR` state files; `-i` via rofi; `Reminder` indicator re-enabled). **`tailscale`/`dropbox` dropped.** See [deltas.md](deltas.md) Phase 9 rows.                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | speedtest measured 1173 Mbps live ✓; wifiqr/disk render centred, no black-out ✓; reminders fire on time ✓                                                                                                                                 |

Rollback at any phase: `shell.json` `bar.enabled=false` + re-add polybar to
i3 autostart; QS host keeps serving panels/OSD.

---

## 11. Risks & open questions

- **QS 0.3.0 pinned local build** — no Devuan package; the from-source build must be
  kept reproducible. `PanelWindow`/`exclusiveZone`/`Quickshell.I3` confirmed present;
  `Pipewire`/`IdleMonitor`/`WlSessionLock`/`ToplevelManager` confirmed **absent** on X11.
- **`plugins/bar/Bar.qml` strut under i3 + picom `glx`** — needs the Phase 8 spike;
  layer/stacking of a dock window under a non-compositing WM may differ from Hyprland.
  Scope is one window (drag-ghosts dropped).
- **Light themes** — first time the whole X11 chain renders `mode="light"`; Phase 1
  must include a real look-test, especially `apply.sh`'s lighten/darken direction.
- **`omarchy-theme-set` reload fan-out** — polybar has no live reload; must restart it
  (brief flicker). dunst/picom via signal. Acceptable.
- **`OMARCHY_PATH` under i3** — no uwsm; set via `omarchy-launch-shell` wrapper, not
  the session env. Any vendored `bin/omarchy-*` that reads `OMARCHY_PATH` needs the
  same export in its shebang preamble or a sourced `omarchy-env`.
- **`systemd-cat` / `loginctl` / `checkupdates`** — Devuan has elogind (`loginctl` ok),
  no `systemd-cat` (→ `logger`), no `checkupdates` (→ `apt`).
- **Stale `I3SOCK`** (fixed 2026-08-31) — i3's `/proc/<pid>/environ` keeps the
  socket path from its *first* start (`ipc-socket.<old-pid>`) across an in-place
  restart; anything i3 `exec`s inherits it, and `i3-msg` prefers `$I3SOCK` over
  the live `I3_SOCKET_PATH` X property → workspace-click / logout silently fail.
  Fix: `unset I3SOCK` in `i3_bar` + `i3_autostart` (session-wide) and defensively
  in the `i3-msg` call sites (`Workspaces.qml`, `scripts/power.sh`).
- **Notification daemon race** (fixed 2026-08-31) — three providers claim
  `org.freedesktop.Notifications` on the bus (dunst, xfce4-notifyd, lxqt-notificationd);
  `xfce4-power-manager` D-Bus-activates xfce4-notifyd, which then wins the name and
  `dunstctl` fails (`No such interface org.dunstproject.cmd0`). Fix: a user-dir
  activation override `~/.local/share/dbus-1/services/org.freedesktop.Notifications.service`
  → `Exec=dunst`, `i3_dunst` runs **before** `xfce4-power-manager` in `i3_autostart` and
  kills xfce4-notifyd/lxqt-notificationd by full path.
- ~~`shell.toml.tpl` `hyprland_active_border`~~ — **retracted** (Phase 1): the
  templater falls back to `accent` on its own; no override needed.
- **Tray under QApplication** — `//@ pragma UseQApplication` already in local `shell.qml`;
  keep it when mirroring upstream (upstream may use `QGuiApplication`).
- **`deltas.md` discipline** — the whole "track upstream" premise depends on every
  divergence being logged there; without it a `omarchy-quattro` bump silently clobbers
  X11 fixes.

### All open points resolved

| Point                 | Resolution                                                                                                        |
| --------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Theme fan-out         | WM chrome + terminals + GTK(icon/variant only), no editors; btop/chromium wired-off. → decisions 5, GTK Option A. |
| System stats          | Keep `cpu`/`gpu`/`memory` as 3 readouts; no `panels/monitor`. → decision 6.                                       |
| AI agents             | `plugins/agents` + `model-usage` not ported; no collectors. → decision 7.                                         |
| CLI keybinds          | Drop `Alt+Ctrl+*`; btop→`Super+Ctrl+T`, music→`Super+Shift+M`. → decision 8.                                      |
| Editor key            | `Super+Shift+N` → **Sublime** (`$text_editor`), no nvim bind.                                                     |
| Screen zoom / scaling | `Super+Ctrl+Z`, `Super+/` **unbound**.                                                                            |
| tailscale / dropbox   | **Dropped** — not used.                                                                                           |
| `Super+X`             | **Freed** (system menu is `Super+Escape`, no alias).                                                              |
| Workspaces            | **1–10** confirmed.                                                                                               |
| `deltas.md`           | **Seed now**, Phase 0.                                                                                            |
| GTK                   | **Option A** — keep one installed GTK theme; per-switch changes only icon theme + light/dark variant.             |

---

## 12. Dependencies (Devuan)

Already covered by `AGENTS.md` + adds:
`quickshell` (from source, pinned) · `rofi` · `polybar` · `picom` · `dunst` ·
`i3-wm` · `xprintidle` · `xss-lock` or `xautolock` · `maim` `slop` `ffmpeg`
(capture) · `xwallpaper` or `feh` · `qrencode` (`wifiqr`) · `playerctl` `mpc`
(media) · `pactl` (pulseaudio-utils / pipewire-pulse) · `brightnessctl` or `light` ·
`upower` · `bluez` (`bluetoothctl`) · NetworkManager (`nmcli`) · `jq` ·
`xclip`/`xsel` · `inotify-tools` (`inotifywait` — Phase 3 `PluginRegistry`
third-party plugin watch; missing → a harmless 1s retry loop) ·
`python3-xlib` (`scripts/focus-window.py` — the `XSetInputFocus` that lets
the launcher/runner search boxes receive keys under i3; **without it typing
in those popups silently does nothing**) ·
fonts: JetBrainsMono Nerd Font + Symbols Nerd Font (installed).
Optional: `clipmenu`/`greenclip` · `rofimoji` · `xzoom`/`boomer`.
