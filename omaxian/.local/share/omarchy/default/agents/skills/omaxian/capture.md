# Capture

Read this before taking screenshots or picking colors on the desktop.

Omaxian does not ship `omarchy screenshot`, `omarchy capture`, or
`omarchy screenrecord`. Use the i3 screenshot script (`maim` + `xclip`).

## Screenshots

Keybind: **Super+Ctrl+C** (runs `~/.config/i3/scripts/i3_screenshot` with no
mode — that prints usage). For an actual capture, pass a flag or bind one:

```bash
~/.config/i3/scripts/i3_screenshot --now     # full screen, clipboard + Pictures/Screenshots
~/.config/i3/scripts/i3_screenshot --area    # drag a region
~/.config/i3/scripts/i3_screenshot --win     # focused window
~/.config/i3/scripts/i3_screenshot --in5     # delay 5s
~/.config/i3/scripts/i3_screenshot --in10    # delay 10s
```

Files land in `$(xdg-user-dir PICTURES)/Screenshots` and are copied to the
clipboard as `image/png`. `flameshot` is also installed by `setup.sh` if the
user wants an interactive annotator.

## Screen recording

Not ported. Do not call `wf-recorder`, `wl-screenrec`, or `omarchy screenrecord`.
If the user already has `ffmpeg` / `simplescreenrecorder` / similar, use that.

## Color picker

**Super+P** (release) runs `~/.config/i3/scripts/i3_colorpicker` (`gpick`).
This replaces Arch `xcolor`.

## Clipboard

`xclip` (not `wl-copy`). Example: `xclip -selection clipboard -t image/png`.
