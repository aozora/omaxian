# Phase 1 — theme engine (build log)

Status: **core built + repo-side activation edits done** (2026-08-30). The config
tree now expects the theme engine; the **live machine steps remain** — deploy the
config, create the `~/.local/share/omarchy` symlinks, then run the
`omarchy-theme-set` look-test. See "Activation" (checklist state inline) and
"Remaining — run on the live machine" below.

## Deployment topology (decision)

`OMARCHY_PATH=$HOME/.local/share/omarchy` — a mirror of the `omarchy-quattro/`
repo root. The Quickshell tree lives at `$OMARCHY_PATH/shell/` (Phase 3
decision, 2026-08-31: the repo dir moved from `marcello/.config/quickshell/`
to `marcello/.local/share/omarchy/shell/`, matching upstream's
`quickshell -p "$OMARCHY_PATH/shell"`).

| Path | Source | Deploy |
|---|---|---|
| `$OMARCHY_PATH/themes/` | pure upstream (`colors.toml` + `backgrounds/` consumed as-is) | `cp -r` ← `<dotfiles>/omarchy-quattro/themes` |
| `$OMARCHY_PATH/default/` | pure upstream (`default/themed/*.tpl`) | `cp -r` ← `<dotfiles>/omarchy-quattro/default` |
| `$OMARCHY_PATH/shell/` | marcello mirror + X11 deltas | `cp -r` ← `marcello/.local/share/omarchy/shell/` (Phase 3+); optional back-compat `~/.config/quickshell` → `$OMARCHY_PATH/shell` symlink |
| `$OMARCHY_PATH/bin/` | vendored + adapted scripts | `cp -r` ← `marcello/.local/share/omarchy/bin/` (real files, on `$PATH`) |
| `~/.config/omarchy/themed/` | **our** X11 templates | `marcello/.config/omarchy/themed/` |
| `~/.config/omarchy/themes/` | user-installed themes (empty for now) | `marcello/.config/omarchy/themes/` |
| `~/.config/omarchy/shell.json` | bar/plugin config (Phase 3+) | — |
| `~/.local/state/omarchy/` | runtime state — **never committed** | created at first run |

**Decision (2026-08-30):** the live `~/.local/share/omarchy` tree is a detached
**copy** of the repo, not symlinks — the repo stays independent of the running
system. Cost: ~143 MB of theme backgrounds are duplicated, and an
`omarchy-quattro/` bump or `bin/` edit needs step B re-run to take effect.

## What was built

### Vendored **verbatim** (pure bash/awk/sed, zero platform deps)
`marcello/.local/share/omarchy/bin/`:
- `omarchy-theme-color` — the `colors.toml` resolver. Emits every semantic key
  + ANSI aliases + derived shades + `mode` (light/dark, auto-detected from bg
  luminance when unset). Every other consumer resolves the identical palette
  through this.
- `omarchy-theme-set-templates` — renders `$OMARCHY_PATH/default/themed/*.tpl`
  **and** `~/.config/omarchy/themed/*.tpl` into `next-theme/<name>` via a
  generated `sed` script. Supports `{{ key }}`, `{{ key_strip }}`,
  `{{ key_rgb }}`, `{{ mix a b 30% }}`, `{{ shell_gradient ref fallback }}`, …
- `omarchy-theme-list`, `omarchy-theme-current`, `omarchy-theme-dir`,
  `omarchy-theme-refresh`.

### Adapted for X11
- `omarchy-theme-set` — keeps upstream's stage → `omarchy-theme-set-templates`
  → atomic `mv` → `theme.name` → `flock` flow. Replaces the
  Hyprland/systemd/PipeWire reload block with:
  `reload_quickshell` (`omarchy-shell shell applyTheme <b64>`, best-effort —
  the QS `FileView` also catches the swap) · `reload_i3` (`i3-msg -q reload`) ·
  `reload_polybar` · `reload_dunst` (in-place `awk` of the 3 `[urgency_*]`
  sections + `dunstctl reload`) · `reload_gtk` (**Option A** — icon theme from
  `icons.theme` + `prefer-dark` from `mode`, nothing else) · `reload_terminals`
  (kitty `SIGUSR1`; alacritty self-watches) · `set_background`
  (`xwallpaper --zoom` / `feh --bg-fill` + `current/background` symlink).
- `omarchy-restart-polybar` — `killall polybar` + re-run
  `~/.config/i3/themes/polybar.sh`.
- `omarchy-restart-terminal` — kitty `SIGUSR1`.

### New
- `omarchy-theme-next` — cycle through `omarchy-theme-list`.
- `omarchy-theme-menu` — `rofi -dmenu` picker → `omarchy-theme-set`.

### Templates — `marcello/.config/omarchy/themed/`
Only the **include-consumer** configs (rendered into `current/theme/`, the app
`include`s them). dunst/picom/GTK are patched in place by `omarchy-theme-set`
instead (no include mechanism).

| `.tpl` | → `current/theme/` | consumed by |
|---|---|---|
| `i3.conf.tpl` | `i3.conf` | i3 `include` at end of `config` — the 8 `set $i3_cl_col_*` + 6 `client.*` lines |
| `polybar.ini.tpl` | `polybar.ini` | polybar `include-file` (replaces `themes/default/polybar/colors.ini`) |
| `colors.rasi.tpl` | `colors.rasi` | rofi — `themes/default/rofi/shared/colors.rasi` becomes a symlink to it |

Palette mapping (mirrors the old `apply_i3_theme.sh`): focused=`accent`,
focused_inactive=`blue`, unfocused=`lighter_background`, urgent=`magenta`,
indicator=`green`, bg/placeholder=`background`, text=`background`(on focused)/
`foreground`(elsewhere). polybar `ALTBACKGROUND=lighter_background`,
`ALTFOREGROUND=dark_foreground`, ANSI 0-15 from `omarchy-theme-color`'s
canonical map (`color0=background`, `color8=muted`, …).

### Not needed after all
`shell.toml.tpl`'s `{{ shell_gradient hyprland_active_border accent }}` — the
templater's `resolve_theme_ref` **already** falls back to `accent` when
`hyprland_active_border` is undefined. No `.tpl` patch, no fed variable.
(omarchy-migration.md §7 risk item retracted.)

### Rendered-but-unused
`omarchy-theme-set-templates` also renders upstream's `hyprland.lua`,
`foot.ini`, `ghostty.conf`, `neovim.lua`, `vscode-theme.json`, `obsidian.css`,
`helix.toml`, `btop.theme`, `chromium.theme`, `claude.json`, `keyboard.rgb`,
`gum_env.lua`, `pi.json`, `kitty.conf`, `alacritty.toml`, `shell.toml` into
`current/theme/`. Only `alacritty.toml`, `kitty.conf`, `shell.toml` (+ our 3)
are wired to a consumer; the rest are inert files (decision 5). Pruning them is
optional polish, not required.

## Verified (sandbox `HOME`, no live change)

`omarchy-theme-set-templates` run against `tokyo-night` (dark),
`catppuccin-latte` (light), `gruvbox` (dark):

- `i3.conf` — correct per-theme `client.*` colors, light themes invert cleanly
  (`catppuccin-latte` bg `#eff1f5`, fg `#4c4f69`).
- `polybar.ini` — 22 keys, no stale Mocha/Macchiato mismatch.
- `colors.rasi` — 6 rofi tokens.
- `omarchy-theme-color … --all` — 60+ resolved keys incl. `mode`.
- `omarchy-theme-list` — 22 themes.

## Activation

Repo-side edits — **done 2026-08-30** (commit follows):

1. ~~Deploy symlinks~~ — **not a repo edit**; see "Remaining" below.
2. **PATH + env** — `scripts/i3_autostart` exports `OMARCHY_PATH` +
   prepends `$OMARCHY_PATH/bin` to `PATH`, right after `XDG_CURRENT_DESKTOP`. ✅
3. **Bootstrap the state dir** — `i3_autostart`, just before `scripts/i3_bar`:
   `[ -f …/current/theme/polybar.ini ] || omarchy-theme-set "Tokyo Night"`.
   (polybar's `include-file` is fatal if missing; i3's `include` is not.) ✅
4. **i3** — `config` gains `include ~/.local/state/omarchy/current/theme/i3.conf`
   right after the `config.d/*` include. `config.d/01_theme.conf` — the 8
   `set $i3_cl_col_*` lines and the `client.*` / `client.background` block are
   deleted (replaced by comments pointing at the rendered `i3.conf`). ✅
5. **polybar** — `themes/default/polybar/config.ini`: `./colors.ini` include
   commented out, replaced by `include-file = ~/.local/state/omarchy/current/theme/polybar.ini`.
   `colors.ini` kept in the repo for rollback. ✅
6. **rofi** — `themes/default/rofi/shared/colors.rasi` is now a symlink →
   `~/.local/state/omarchy/current/theme/colors.rasi` (absolute; survives the
   copy-deploy). Old content saved as `colors.rasi.static-fallback`. The
   `@import "colors.rasi"` in `shared/base.rasi` resolves through it. ✅
7. **Keybind** — `02_keybindings.conf`: `$ALT+Control+t` → `omarchy-theme-menu`,
   `$ALT+Control+Shift+t` → `omarchy-theme-next`. Omarchy's own chord is
   `Super+Ctrl+Shift+Space`, but this box runs `setxkbmap grp:win_space_toggle`
   (i3_autostart), so the X server eats every `Super+Space` combo for layout
   switching before i3 sees it. (`$ALT+Control+t` was a commented-out kitty
   bind.) Phase 7's keybinding rewrite can revisit. ✅

## Remaining — run on the live machine

A. **Deploy** the updated `marcello/.config/i3` tree to `~/.config/i3` (copy;
   no stow on this box).
B. **Populate `~/.local/share/omarchy` + the config dir** (the live tree is a
   detached *copy* of the repo — re-run after any `omarchy-quattro/` bump or
   `bin/` change to refresh it). The `rm -rf` keeps re-runs from nesting a
   `themes/themes/`:
   ```
   mkdir -p ~/.local/share/omarchy ~/.config/omarchy/{themes,themed}
   rm -rf ~/.local/share/omarchy/{themes,default,bin}
   cp -r ~/projects/dotfiles/omarchy-quattro/themes  ~/.local/share/omarchy/themes   # ~143 MB
   cp -r ~/projects/dotfiles/omarchy-quattro/default ~/.local/share/omarchy/default
   cp -r ~/projects/dotfiles/marcello/.local/share/omarchy/bin ~/.local/share/omarchy/bin
   ```
   (`cp -r` keeps the `bin/` scripts executable. No symlinks inside either
   source tree, so no `-L` needed.)
C. **First render**: `OMARCHY_PATH=~/.local/share/omarchy PATH=~/.local/share/omarchy/bin:$PATH omarchy-theme-set "Tokyo Night"`
   then `i3-msg reload` (or just re-login — `i3_autostart` does B's bootstrap +
   env on its own once deployed).
D. **Look-test** (plan step 8): `omarchy-theme-set "Gruvbox"` → i3 borders,
   polybar, rofi, dunst, wallpaper, kitty all move. Then `omarchy-theme-set
   "Flexoki Light"` — eyeball picom shadows / border contrast / dunst / polybar
   `ALTBACKGROUND` direction on a light `mode`.

Verified in a sandbox `HOME` on 2026-08-30 with the activation templates in
place: `omarchy-theme-set "Tokyo Night"` renders a syntactically clean
`i3.conf` (8 vars + 6 `client.*`), `polybar.ini` (all 13 keys the polybar
modules reference are present), and `colors.rasi` (6 rofi tokens);
`theme.name` = `tokyo-night`.

## Deferred to later phases

- picom: no per-theme color today (`shadow-color` commented, `corner-radius 0`).
  The `quickshell` `WM_CLASS` shadow/round exclusion is Phase 8.
- GTK Option B (generated `gtk.css`) — only if GTK apps visibly clash.
- Pruning unused rendered theme files.
- `omarchy-theme-set` calling the real `omarchy-shell` IPC — needs Phase 3 host.
- alacritty/kitty `import`/`include` lines pointing at `current/theme/*` — verify
  the live terminal configs actually import them (Phase 1 activation step, add if missing).
