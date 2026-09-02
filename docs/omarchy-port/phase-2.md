# Phase 2 — Commons / Ui mirror (build log)

Status: **done in the repo + smoke-tested** (2026-08-30). `quickshell -p
<repo tree>` loads clean ("Configuration Loaded", zero stderr warnings) with
both the widgets-only and full-bar paths. **Not yet deployed / eyeballed** —
see "Remaining" below.

Decision (asked 2026-08-30): **verbatim upstream mirror** of `Commons/` +
`Ui/`, not the "keep the local flat schema" reading of deltas.md's old
`Color.qml` row.

## What changed

### `Commons/` — mirrored verbatim from `omarchy-quattro/shell/Commons/`
- `Color.qml` — **byte-identical to upstream** now. Was a hardcoded-Catppuccin
  local design with bespoke `bar.*` / `popups.*` / `tooltip` sub-objects.
  Upstream exposes only `foreground` / `background` / `accent` / `urgent` /
  `muted` + `shellValues` + the `bar` / `popups` / `menu` / `polkit` / `lock`
  / … surface set.
- `Util.qml` — verbatim (marcello was missing `wheelSteps()` / `execArgv()`).
- `Border.qml`, `qmldir` — already identical.
- `BorderGeometry.js` + `Ui/BorderOverlay.qml` — reset to upstream's
  winding-path renderer (marcello had an older `ringPath` / `OddEvenFill`
  pair — drift).
- `Style.qml` — upstream **minus** the `drop-hyprctl` delta: removed
  `hyprctlProc` / `gapsOutProc` / `refreshTimer` / `windowNoGapsToggle`
  (Hyprland `getoption` sync) **and** `fcMatchProc` / `fontconfigFile`
  (`fc-match` font resolution) + their `Component.onCompleted`. Kept
  `applyShellValues` and every state-color / spacing / font resolver
  verbatim. `cornerRadius` / `radiusPopup` / `gapsOut` are static `8` / `12`
  / `8`; `resolvedFontFamily` stays `"monospace"`. `import Quickshell.Io`
  dropped; `import Quickshell` kept (for `Quickshell.env`).

### `Ui/` — mirrored verbatim from `omarchy-quattro/shell/Ui/`
- Every file reset to upstream (the diffs were almost all a missing
  `textFormat: Text.PlainText` catch-up + `PanelHero.trailingControl`).
- **Deltas re-applied on top of upstream:** `PopupCard.qml` (`T2` — `PopupWindow`
  + `grabFocus`, `centerOnBar`, `radius: Style.radiusPopup`),
  `KeyboardPanel.qml` (`T1` — `focusable` instead of `WlrLayershell`
  keyboard-focus + dismiss windows).
- Added `ScreenMoveRemap.qml` (`import QtQuick` only) + `ToggleSwitch.qml`
  (needed by the mirrored `Toggle.qml` / `PanelHero.qml`) + their `qmldir`
  lines.
- **Omitted `SpeedTestOverlay.qml`** (+ its `qmldir` line): `import
  Quickshell.Wayland`, unused in the ported tree. Phase 9 `T1` if the
  speedtest panels are ever ported.

### New: `Services/BarPalette.qml` (`local` singleton, `qs.Services`)
Holds everything the verbatim `Color.qml` no longer provides that the local
Bar widgets need:
- Named `colors.toml` tokens (`red green blue cyan yellow orange magenta
  brown` + `selection` / `lighter_background` / `dark_foreground`) read via
  its own `FileView` on `~/.local/state/omarchy/current/theme/colors.toml`
  (`watchChanges: true` — startup-correct always, live-swap best-effort until
  the Phase 3 IPC host).
- `separator` / `menuLogo` / `chipBackground` / `mpd` / `timer` / `weather`
  / `volume` / `bluetooth` / `network` / `vpnOn` / `vpnOff` / `updates` /
  `date` / `battery` / `power`, a `workspace.*` sub-object (10 roles), and
  `popupSubtext` / `popupInputBackground` / `popupHeaderAccent` /
  `popupHelpKeys` / `popupWeatherAccent` — all derived from the named tokens
  + `Color`'s roles.

### Bar consumers — token swap (17 files)
`Bar/widgets/{MenuButton,WallpaperButton,HelpButton,Bluetooth,Volume,Vpn,
Updates,Mpd,Network,Weather,Workspaces,Clock,Timer,Separator,Battery,
PowerButton}.qml` + `Bar/WindowsPopup.qml`:
- `Color.bar.workspace.X` → `BarPalette.workspace.X`
- `Color.bar.<semantic>` → `BarPalette.<semantic>` (`Color.bar.background` /
  `.text` / `.active` kept — upstream has them)
- `Color.popups.{subtext,inputBackground,headerAccent,helpKeys,weatherAccent}`
  → `BarPalette.popup*`
- each gained `import qs.Services`

`Bar/Bar.qml` and the other widgets (`KeyboardLayout`, `Tray`,
`Notifications`, `SysStats`) were already on upstream-safe tokens
(`Color.bar.background` / `.text`, `Color.popups.text`, `Color.muted`,
`Color.urgent`, `Style.*`) — untouched.

## Verified (2026-08-30, sandbox — no live change)
- `quickshell -p <repo> -n` with `QS_WIDGETS_ONLY=1` → "Configuration Loaded",
  no stderr.
- same without `QS_WIDGETS_ONLY` (full bar builds) → "Configuration Loaded",
  no stderr.
- Full-tree grep: no dangling `Color.bar.<semantic>` / `Color.popups.<extra>`.

Pre-Phase-2 `Commons/` + `Ui/` snapshot kept at
`…/scratchpad/qs-pre-phase2/` for the session.

## Remaining — on the live machine
A. Deploy `marcello/.local/share/omarchy/shell` → `~/.local/share/omarchy/shell` **and**
   `Services/BarPalette.qml` (new file) — then `qs kill` / restart the
   running instance (or re-login).
B. **Eyeball** (the plan's Phase 2 verify): bar renders, per-widget colours
   look right (mpd green, weather yellow, updates orange, workspace pills),
   popups (calendar, weather, help, windows, wallpaper, menu) open themed.
   The smoke test only proves it compiles + instantiates, not that bindings
   render sensibly.
C. Theme-swap while running (`omarchy-theme-set "Gruvbox"`): `Color`'s 5
   roles won't move yet (upstream `colorsFile` is `watchChanges: false`,
   startup-only — live recolour needs the Phase 3 `omarchy-shell applyTheme`
   IPC). `BarPalette`'s `FileView` is `watchChanges: true` so the bar's
   named-token colours *may* follow; treat any live movement as a bonus, not
   a Phase 2 requirement.

## Known regression (accepted with the "verbatim mirror" choice)
Upstream `Color.qml`'s 5-role palette can't express per-widget colour coding
on its own; `BarPalette` restores it by reading `colors.toml` directly. If
that file is dropped at Phase 8 (real `plugins/bar` + `shell.toml` surfaces),
the semantic bar colours come back through the registry instead.
