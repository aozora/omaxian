# Themes, Backgrounds, and Fonts

Read this before changing themes, backgrounds, fonts, or theme colors.

## Theme commands

```bash
omarchy-theme-list              # Show available themes
omarchy-theme-current           # Show current theme
omarchy-theme-set <name>        # Apply theme ("Tokyo Night" and "tokyo-night" both work)
omarchy-theme-bg-next           # Cycle background
omarchy-theme-next              # Next installed theme
```

That restyles the bar, i3, dunst, GTK icons, kitty, picom (where templated),
and the wallpaper (`feh`). There is no `omarchy theme install` dispatcher;
clone a theme repo into `~/.config/omarchy/themes/<slug>/` yourself if needed.

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

## Fonts

There is no `omarchy font` command. UI size is Settings → Appearance
(`[font] base-size` in `~/.config/omarchy/shell.toml`). The bar needs a Nerd
Font (JetBrains Mono is the default). Window titles: `$i3_fonts` in
`~/.config/i3/config.d/01_theme.conf`.
