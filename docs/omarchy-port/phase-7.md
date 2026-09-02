# Phase 7 — keybindings + polybar trim (build log)

Status: **done in the repo 2026-08-31.** `i3 -C` validates the merged config
(no syntax errors, no duplicate-binding warnings). Not yet deployed / used.

Goal (migration §10 / §9): rewrite `config.d/02_keybindings.conf` to Omarchy's
Super-centric scheme, regenerate the help sheet, trim polybar modules (§8).

## Files changed

- **`config.d/02_keybindings.conf`** — rewritten from §9a resolutions + §9b
  additions + §9d retentions (114 binds).
- **`config.d/03_mousebindings.conf`** — added `Super+button4/5` = workspace
  prev/next (§9b).
- **`config.d/04_modes.conf`** — dropped the `$MOD+Shift+m` → "Move" mode
  trigger (that chord is now *music*, §9b). Mode kept, unbound.
- **`themes/default/polybar/config.ini`** — `modules-right` trimmed to §8:
  dropped `timer` / `help` from the layout (`vpn` / `wallpapers` were
  already out). Definitions stay in `modules.ini`.
- **`themes/default/rofi/help-keybindings.txt`** — regenerated to the new map.
- **`scripts/i3_help`** — dropped the stale `~/.config/quickshell` path; now
  `omarchy-shell help toggle` (→ local Bar `help` IPC) with the rofi/less
  fallback.

## §9 as implemented — the semantic swaps (9a)

| Chord | now |
|---|---|
| `Super+Tab` / `Super+Shift+Tab` | workspace next / prev (was `focus next`) |
| `Alt+Tab` / `Alt+Shift+Tab` | cycle windows on workspace |
| `Super+W` / `Super+Q` / `Super+C` | kill |
| `Super+T` | floating toggle |
| `Super+J` | split orientation toggle |
| `Super+G` | `layout toggle tabbed split` (9c: no Hyprland groups) |
| `Super+S` / `Super+Shift+S` | scratchpad show / move-to-scratchpad |
| `Super+M` | *freed*; music → `Super+Shift+M` |
| `Super+N` | *freed*; network → `Super+Ctrl+W`; editor → `Super+Shift+N` |
| `Super+B` | *freed*; former-workspace → `Super+Ctrl+Tab`; bluetooth → `Super+Ctrl+B` |
| `Super+X` | *unbound*; power/session → `Super+Escape` |
| `Super+Minus`/`Super+Equal` (+Shift/+Alt/+Ctrl) | resize edges (replaces `Super+Alt+arrows`) |

## Deviations from §9 (and why)

1. **`Super+Space` family is unusable.** `i3_autostart` runs `setxkbmap …
   grp:win_space_toggle`, so the X server consumes every `Super+Space` combo
   for keyboard-layout switching before i3 sees it (confirmed in Phase 1).
   So:
   - `Super+Space` (Omarchy menu) → **launcher stays on `Super+L`.** §9a only
     moved it to vacate `Super+L` for a Wayland layout mode i3 doesn't have,
     so there's no real conflict keeping it.
   - `Super+Alt+Space` (apps) → **`Super+Alt+L`** (`rofi -show drun`).
   - `Super+Shift+Space` (§9d focus mode_toggle) → **kept as-is**; it may not
     fire under `grp:win_space_toggle`. Rebind if you need it.
   - Permanent fix if wanted: switch the xkb toggle to e.g.
     `grp:alt_shift_toggle` / `grp:caps_toggle` and restore the real §9
     Super+Space chords.
2. **No `omarchy-menu`** vendored (decision 4 keeps rofi). `Super+Space`'s
   "menu" role folds into the launcher; `Super+Escape` → `rofi_powermenu`.
3. **System panels are interim.** `Super+Ctrl+{A,B,W,P,D}` point at
   `rofi_bluetooth` / `network_menu` / `rofi_powermenu` / `i3_display.sh` /
   `i3_quickshell_toggle` — the real `omarchy.{audio,bluetooth,network,power}`
   panels are `kind: bar-widget` and need the Phase 8 bar engine to summon.
   `Super+Ctrl+Alt+D` → `i3_quickshell_toggle calendar` already works (local
   Bar). `Super+Ctrl+1..4` → `omarchy-shell -q shell togglePanelAt` (no-op
   until Phase 8, harmless).
4. **`Super+Ctrl+T` = btop** (§9b). The theme picker stays on `Alt+Ctrl+T` /
   `Alt+Ctrl+Shift+T` (set in Phase 1 precisely to leave `Super+Ctrl+T` free).
5. **`Super+Shift+/` (password manager)** — commented stub; pick a client.
6. **Screen zoom / monitor scaling** (`Super+Ctrl+Z`, `Super+/`) — unbound
   (§9c decision).
7. **Move mode** — its `$MOD+Shift+M` trigger is gone (music). Re-add on a
   free chord if wanted.

## Verify (live)

- `i3-msg reload` (or restart) — no errors.
- `Super+Escape` → power menu; `Super+K` → help sheet matches;
  `Super+Ctrl+T` → btop; `Super+W`/`Super+Q` → kill; `Super+Tab` → next ws;
  `Alt+Tab` → cycle windows; `Super+Minus/Equal` → resize.
- polybar shows the trimmed `modules-right` (no timer/help pill).
- `Super+L` launcher, `Super+Shift+M` music, `Super+Shift+N` Sublime.
