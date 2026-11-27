# Themes, Backgrounds, and Fonts

Read this before changing themes, backgrounds, fonts, or theme colors.

## Theme commands

```bash
omarchy-theme-list              # Show available themes
omarchy-theme-current           # Show current theme
omarchy-theme-set <name>        # Apply theme ("nebula-ridge" / "Nebula Ridge" both work)
omarchy-theme-bg-next           # Cycle background
omarchy-theme-next              # Next installed theme
```

That restyles the bar, i3, dunst, GTK icons, kitty, picom (where templated),
and the wallpaper (`hsetroot -cover` / `feh`). One image is painted on the
X root for the whole desktop, not per output (see the checkout file
`docs/omaxian/customize/displays.md`). There is no `omarchy theme install`
dispatcher; clone a theme repo into `~/.config/omarchy/themes/<slug>/`
yourself if needed.

## Making a new theme

1. Create a directory under `~/.config/omarchy/themes`.
2. Copy how an existing theme is done from `~/.local/share/omarchy/themes/`.
3. Put backgrounds in `~/.config/omarchy/themes/<name>/backgrounds/`.
4. Run `omarchy-theme-set "Name of new theme"`.

Additional user backgrounds for any theme go in
`~/.config/omarchy/backgrounds/<theme-slug>/` (and Settings can point at an
extra wallpaper folder).

## Customizing a stock theme

Never edit stock themes under `~/.local/share/omarchy/themes/` — `install.sh`
replaces that tree. Two safe options:

**Overlay (preferred for small tweaks):** create a user theme directory with
the SAME slug containing only the files you want to change. When the theme is
applied, the stock theme is copied first and your files win on top:

```bash
mkdir -p ~/.config/omarchy/themes/catppuccin
cp ~/.local/share/omarchy/themes/catppuccin/colors.toml ~/.config/omarchy/themes/catppuccin/
# Edit the copied colors.toml, then:
omarchy-theme-set catppuccin
```

**Fork:** copy the whole stock theme under a new name:

```bash
cp -r ~/.local/share/omarchy/themes/catppuccin ~/.config/omarchy/themes/catppuccin-custom
omarchy-theme-set catppuccin-custom
```

To change how every theme templates an app, put a template in
`~/.config/omarchy/themed/<config-name>.tpl`. This port ships `i3.conf.tpl`
among others. Hyprland `*.lua` templates are unused here.

## Installing themes

```bash
omarchy-theme-install <git-url>   # also Style → Install Theme
omarchy-theme-remove [name]
omarchy-theme-update              # git-installed themes
```

A theme installed from a git repo cannot supply files that run commands
(`i3.conf`, terminal configs, `fastfetch.jsonc`, `.lua`, `vscode.json`) or
symlinks; the generated versions are used instead.

## Window gaps and corners

```bash
omarchy-toggle-window-gaps                  # gaps, borders, rounding off/on
omarchy-window-corners theme|sharp|rounded
```

Both are under **Style → Windows** and survive a deploy and re-login. Do not
edit the generated files under `~/.local/state/omarchy/toggles/`.

## App icon sets

An icon set redraws app icons in the theme's colors. It is chosen separately
from the theme, under **Style → Icons** or with these commands:

```bash
omarchy-icons-list
omarchy-icons-set Arcade       # Original restores each app's own icon
omarchy-icons-current
omarchy-icons-install <git-url>
omarchy-icons-remove <name>
omarchy-icons-update
```

To redraw one icon, add `<Icon= name>.svg.tpl` (or `.svg`) under
`~/.config/omarchy/icons/<set>/`, for example `papercraft/`, then run
`omarchy-icons-set <set>`. Stock sets live in `$OMARCHY_PATH/icons/`; do not
edit them.

## Fonts

There is no `omarchy font` command. UI size is Settings → Appearance
(`[font] base-size` in `~/.config/omarchy/shell.toml`). The bar needs a Nerd
Font (JetBrains Mono is the default). Window titles: `$i3_fonts` in
`~/.config/i3/config.d/01_theme.conf`.
