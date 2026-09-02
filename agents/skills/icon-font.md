# Icon Fonts and Glyphs

Read this before adding or changing icons in the bar, dock, or Omarchy menu.

Omaxian does **not** ship Omarchy's branded `omarchy.ttf` or the
`omarchy dev font` workflow. There is no package-owned
`/usr/share/fonts/omarchy/` tree. The session uses JetBrains Mono (and other
Nerd Fonts) from `omaxian/.local/share/fonts/` plus `fonts-jetbrains-mono` /
`papirus-icon-theme` from apt.

## What to use

- Prefer a Nerd Font / Symbols Nerd Font codepoint for menu entries and bar
  widgets. The menu draws `icon` in the UI font unless `iconFont` is set.
- Papirus names for tray / `.desktop` icons (`Quickshell.iconPath`).
- The left menu glyph is a widget setting (`omaxian.menu` `settings.icon`),
  not a private-use brand mark. The character must exist in the bar font.

Do not add a private-use TTF to this port unless there is an explicit product
decision to vendor one. Do not call `omarchy font …` — those commands are not
shipped.

## Editing files that already contain glyphs

Widget QML under `omaxian/.local/share/omarchy/shell/plugins/bar/widgets/`
embeds Nerd Font glyphs as raw unicode. Agent file-editing tools can strip
multi-byte codepoints — do **not** rewrite those files wholesale. Make a
targeted edit, or insert codepoints with Python `chr(0xXXXXX)`.

After a glyph change, confirm it in the running bar/menu per
[`visual-verification.md`](visual-verification.md). Restart the shell —
Qt reads the font database at startup.
