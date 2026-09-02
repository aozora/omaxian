# Interim UI convergence — Weather & Power widgets

> **Superseded.** This was a 2026-08-30 stopgap for the local `Bar/widgets/Weather.qml`
> + `PowerButton.qml` popups. The live widgets are `omarchy.weather` (Phase 5)
> and `omarchy.power` / `omaxian.powermenu` (Phase 5/8). The Open-Meteo helper
> scripts `shell/scripts/weather.sh` and `weather-forecast.sh` were **deleted
> 2026-09-03**. Kept as history of the interim UI pass.

Status: **applied 2026-08-30** (repo, smoke-tested — `quickshell -p <repo>`
loads clean). Deviations from the plan below:
- Both popups keep the local **`PopupCard`** shell rather than switching to
  `KeyboardPanel` (W2/P1) — identical look when open, `PopupCard`'s X11
  dismissal is already proven here; the `KeyboardPanel` swap (arrow-key nav)
  stays deferred.
- **W3b done** (2026-08-30, 2nd pass): `weather-forecast.sh` now also fetches
  `apparent_temperature` / `relative_humidity_2m` / `wind_speed_10m` in the
  same curl and emits a `current` object; `Weather.qml` renders the
  FEELS / WIND / HUMID row in the hero and prefers `current.temp`/`.icon`
  for the big read-out when the popup fetch has landed.

**Not yet deployed / eyeballed.**

**Goal:** make the *look* of the local `Bar/widgets/Weather.qml` and
`Bar/widgets/PowerButton.qml` match the Omarchy panels as closely as the
current (pre-plugin-host) architecture allows, **without** changing their data
sources, scripts, IPC targets, or the `BarWidget` + `PopupCard` structure.

This is a stopgap until the real ports land — `omarchy.weather` at Phase 8
(plugin host + `Panel.qml` T1 + `omarchy-weather-*` scripts) and the
`omarchy.power` **battery** panel at Phase 5. See
[deltas.md](deltas.md) rows and [migration §6](omarchy-migration.md).

Do **not** touch as part of this:
- `scripts/weather.sh` / `weather-forecast.sh` (Open-Meteo, Milan default) —
  except the one optional additive change in W3 below.
- `scripts/power.sh` / `powermenu-header.sh`.
- IPC targets `weather` / `powermenu`, the `BarWidget` roots, `IpcHandler`
  shapes, `ConfirmDialog` wiring.
- `Services/BarPalette.qml` (Phase 2 — the colour source).

---

## 0. The Omarchy popup visual language (extracted from both upstream panels)

Both `plugins/panels/weather/Panel.qml` and `.../power/Panel.qml` share one
vocabulary. Adopt it verbatim in the two local popups:

| Element | Omarchy treatment |
|---|---|
| Outer container | `KeyboardPanel { centerOnBar: true }` wrapping a `Column { spacing: Style.space(14) }` — **not** a centred `ColumnLayout` with a bold title |
| No title text | upstream panels have **no** "Weather" / "Power" heading — the hero row is the header |
| Hero row | `Item` spanning full width: an oversized glyph on the left, a big bold read-out on the right, optional label stack between |
| Secondary labels | `Qt.darker(bar.foreground, 1.4)`, `.toUpperCase()`, `font.letterSpacing: 1`, `Style.font.caption` or `bodySmall` |
| Values | `bar.foreground`, `Style.font.title` |
| Divider | `Rectangle { height: Style.spacing.hairline; color: bar.foreground; opacity: 0.12 }` (or `Ui/PanelSeparator`) |
| Section header | `Ui/PanelSectionHeader { text: "POWER PROFILE" }` |
| Buttons | `Ui/Button { bordered: true; iconText: "󰌾"; iconSize: Style.font.title; fontSize: Style.font.bodySmall; foreground: bar.foreground }` — glyph via `iconText`, **not** embedded in `text` |
| Rhythm | all gaps/margins through `Style.space(n)` (14 between sections, 16 hero inset, 6–10 within a group) |
| Colours | `bar.foreground` / `Qt.darker(bar.foreground, 1.4|1.5)` / `Color.accent` / `Color.urgent`. No per-widget accent tints in the popup body. |

`bar` here is the `BarWidget`'s injected bar object; it exposes `foreground`
and `fontFamily`. Where a local file currently reads `Color.popups.text` /
`BarPalette.popup*`, switch to `bar.foreground` + the `Qt.darker` ramp to
match upstream exactly.

`KeyboardPanel`, `PanelSectionHeader`, `PanelSeparator`, `PanelHero`, `Button`
(`iconText`/`bordered`/`active`) are all in `Ui/` after the Phase 2 mirror.

---

## 1. Weather — `Bar/widgets/Weather.qml`

Upstream reference: `plugins/panels/weather/Panel.qml` lines ~510–878.

### W1 — Bar pill: icon-only, neutral

| now | → |
|---|---|
| `WidgetButton { text: root.display /* "󰖐 22°" */; foreground: BarPalette.weather }` | `WidgetButton { text: <icon only>; foreground: root.bar.foreground }` — drop the temperature and the yellow tint from the pill; upstream shows just the condition glyph (`BarIconButton`, `slotSize: Style.bar.statusSlot`, no tooltip) |

`root.display` from `weather.sh` is `"<icon> <temp>°C"`. Split on first space:
`iconPart = display.split(" ")[0]`, keep `tempPart` for the popup hero. (Or
add a `--icon-only` mode to `weather.sh` — optional; splitting in QML is
enough.)

### W2 — Popup shell: `KeyboardPanel` + `Column`, no title

Replace `PopupCard { ColumnLayout { … "Weather" title … } }` with:

```
KeyboardPanel {
  anchorItem: button
  owner: weatherOwner
  bar: root.bar
  open: root.menuOpen
  centerOnBar: true
  contentWidth: panel.fittedContentWidth(Style.space(480))
  contentHeight: panel.fittedContentHeight(col.implicitHeight)
  Flickable { … Column { id: col; spacing: Style.space(14) … } }
}
```

Keep `onOpenChanged: if (open) root.refreshForecast()` and the
`weatherOwner` close shim.

### W3 — Hero row (current conditions)

Left: big glyph `font.pixelSize: 64` + big temp `font.pixelSize: 56; bold` +
`"°C"` unit at `Style.font.display`. Source: split `root.display`.

Right (stacked): location label — `"MILAN"` uppercase, `letterSpacing: 1`,
`Qt.darker(fg,1.4)` (static string or `METEO_CITY`; **no** click-to-edit —
upstream's geocode editor needs scripts we don't have). Below it a `Row`
(`spacing: Style.space(36)`) of three `Column`s: **FEELS / WIND / HUMID**
(caption uppercase letterSpacing darker label + `Style.font.title` value).

> `weather.sh` currently emits only icon + temp. Two options:
> - **W3a (min):** omit the FEELS/WIND/HUMID row for now — hero is glyph +
>   temp + location only. Structure matches; three fields blank.
> - **W3b (additive):** extend `weather.sh`'s Open-Meteo `current=` query with
>   `apparent_temperature,relative_humidity_2m,wind_speed_10m` and print a
>   second line / JSON; parse in QML. Small, isolated script change.

### W4 — Divider + forecast row

- Hairline `Rectangle` (fg @ 0.12), visible when `root.daily.length > 0`.
- Centred `Row { spacing: Style.space(44) }` over `root.daily`: each cell is
  `Row { spacing: 10 }` of day-glyph (`Style.font.display`) + `Column`
  (day-name caption uppercase letterSpacing darker / `Row` of `max°` in
  `bar.foreground` body + `min°` in `Qt.darker(fg,1.5)` body).
- This replaces the current "Daily" `Repeater` of full-width `RowLayout`s.

### W5 — Hourly row (local extra, keep or drop)

Upstream has **no** hourly strip. Choose:
- **drop** `root.hourly` + the "Hourly" section (closest to upstream), or
- **keep** it as one extra block *below* the forecast row, restyled to the
  vocabulary (caption labels, `bar.foreground`, no accent tint).

Recommend: keep it, restyled — it's genuinely useful and doesn't fight the
look once the accent tint is gone.

### W6 — Footer

Drop the "Open-Meteo · set METEO_CITY" caption, or shrink it to a single
`Style.font.caption` `Qt.darker(fg,1.6)` line at the bottom of the column
(upstream has no footer).

---

## 2. Power — `Bar/widgets/PowerButton.qml`

**There is no upstream QML to match.** `plugins/panels/power/Panel.qml` is a
**battery + power-profile** panel (battery hero, charge bar, cycles,
`POWER PROFILE` picker); Omarchy's shutdown/reboot/logout menu lives in
`plugins/menu` (the `omarchy-menu` palette — **not** ported, decision 4).

So "match Omarchy" here = **adopt the vocabulary from §0**, keep the local
session-menu concept and `power.sh` / `ConfirmDialog` wiring.

### P1 — Popup shell

`PopupCard` → `KeyboardPanel { centerOnBar: true }` + `Column { spacing:
Style.space(14) }`. (Keeps click-outside dismiss; adds arrow-key nav for
free, matching the upstream panels' feel.) `ConfirmDialog` stays
`anchors.fill: parent` on top.

### P2 — Hero row replaces the centred title + caption

Drop the centred bold "Power" `Text` and the centred caption. Add an
upstream-style hero `Item`:
- left: power glyph `󰐥` at `Style.font.display`, `bar.foreground`
- middle `Column`: `"Power"` (`Style.font.title`, bold) over
  `root.headerText.toUpperCase()` (`Style.font.caption`, `letterSpacing: 1.2`,
  `Qt.darker(fg,1.4)`) — `powermenu-header.sh` output (uptime) becomes the
  status line, exactly like the battery panel's status line.

`Ui/PanelHero` can supply this directly:
`PanelHero { title: "Power"; meta: root.headerText; iconComponent: <glyph> }`.

### P3 — Action grid → upstream Button styling

Keep the 3×2 `GridLayout`, but each `Button`:

| now | → |
|---|---|
| `text: "󰌾  Lock"` (glyph baked into label) | `iconText: "󰌾"; iconSize: Style.font.title; text: "Lock"` |
| `fontSize: Style.font.body * 2`, padding `* 2`, `Layout.preferredHeight: Style.space(70)` | `fontSize: Style.font.bodySmall`, `horizontalPadding: Style.spacing.controlPaddingX`, `verticalPadding: Style.spacing.controlPaddingY + Style.space(2)` — upstream profile-button sizing (the "make them huge" request is dropped in favour of parity) |
| `bordered: true` | keep |
| Reboot/Shutdown `foreground: Color.urgent` | keep |
| others: default | `foreground: root.bar.foreground` |

### P4 — Group split with `PanelSeparator`

Optional but matches upstream's sectioning: split the grid into
**session** (Lock · Logout · Suspend · Hibernate) and **power** (Reboot ·
Shutdown) with a `PanelSeparator { foreground: root.bar.foreground }` and a
`PanelSectionHeader { text: "POWER OFF" }` between, instead of one flat 3×2.

---

## 3. Order of work

1. **W1** + **P3** (pill + button restyle) — smallest, highest visual payoff,
   no structural risk.
2. **W2/W4** + **P1/P2** (popup shell → `KeyboardPanel` + hero) — the bulk.
3. **W3b** (weather script fields) — only if the FEELS/WIND/HUMID row is
   wanted.
4. **W5/W6**, **P4** — polish.

## 4. Verification

Per-widget, on the live machine (needs the GUI session):
- `quickshell -p <repo>` still loads clean (`Configuration Loaded`, no
  stderr) — run after each of the 4 steps.
- polybar click `qs ipc call weather toggle` / `qs ipc call powermenu toggle`
  still opens/closes each popup.
- Weather: glyph-only pill; popup hero shows glyph + temp + `MILAN`; 4-day
  forecast row centred; theme-swap recolours it (via `BarPalette`/`bar`).
- Power: hero row with uptime status line; bordered icon buttons; Reboot/
  Shutdown red; `ConfirmDialog` still gates every action except Lock;
  `power.sh` actions still fire.
- Side-by-side against `omarchy-quattro/shell/plugins/panels/{weather,power}/
  Panel.qml` screenshots (or a Hyprland box) for spacing/typography parity.

## 5. Known gaps vs upstream (accepted for the interim)

- Weather: no click-to-edit location / geocode suggestions (needs
  `omarchy-weather-location` + geocode API); no wttr.in current-conditions
  (Open-Meteo only); imperial/metric is whatever `weather.sh` emits.
- Power: still a session menu, not the battery/power-profile panel; no
  keyboard profile cursor; `PanelHero` status line is uptime, not charge
  state.
- Both keep `PopupCard`/`KeyboardPanel` as local instances, not
  `PluginRegistry`-hosted panels — so no `settings` form, no popout
  coordination with other panels. Resolved when the real ports land.
