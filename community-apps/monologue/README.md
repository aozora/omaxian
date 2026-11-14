# Monologue (Omaxian port)

Qt Quick webcam recorder. Pick a camera and microphone, press Space to record,
then trim the take and save an H.264 MP4. Upstream 0.4.0 adds live Omarchy
language sync (`Translator` + embedded catalogs) and other feature work; see
[`README.upstream.md`](README.upstream.md).

Port of [omacom/monologue](https://github.com/omacom/monologue) **0.4.0**
(upstream commit `add2122d`, full SHA in `.omaxian-upstream-commit`).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| `omarchy pkg add` / `makepkg` (`bin/install`) | Debian `install.sh` → `~/.local`. Arch script kept as `bin/install.arch` |
| CMake build (`./bin/build`) | Same; upstream dropped qmake/`.pro` |
| Wayland session, `qt6-wayland` on the desktop | XCB via `qt6-qpa-plugins`. No Wayland module |
| Corner radius from `hyprctl` | Unchanged; already gated on `HYPRLAND_INSTANCE_SIGNATURE` (square corners on i3) |
| File chooser via xdg-desktop-portal | Same, with `xdg-desktop-portal-gtk` |
| Theme accent from `colors.toml` | Unchanged (`~/.local/state/omarchy/current/theme/colors.toml`) |
| Qt Multimedia from the system Qt | When `qml6-module-qtmultimedia` is not installed for the running Qt, `~/.local/bin/monologue` is a wrapper. It adds `~/.local/lib` to `LD_LIBRARY_PATH`, `~/.local/lib/qt6/qml` to `QML_IMPORT_PATH`, and `~/.local/lib/qt6/plugins` to `QT_PLUGIN_PATH`. The real binary is `~/.local/libexec/monologue` |

Camera capture (Qt Multimedia / FFmpeg / V4L2) and the microphone (PulseAudio
or pipewire-pulse) are unchanged.

## Requirements

Runtime (also in `omaxian.deps.json`):

- Qt 6.8 or newer: Quick, Quick Controls, Multimedia (`libqt6multimedia6`, `qml6-module-*`)
- `ffmpeg`, `libpulse0`
- `xdg-desktop-portal` and `xdg-desktop-portal-gtk`
- `qt6-qpa-plugins` (XCB)

Build: `cmake`, `qt6-base-dev`, `qt6-declarative-dev`, `qt6-multimedia-dev`,
`libpulse-dev`, `libturbojpeg0-dev`. Stock Devuan Excalibur ships Qt 6.8.2,
which meets upstream's Qt ≥ 6.8 line.

## Install

```bash
community-apps/monologue/install.sh
```

`install.sh` refuses to apt-install Qt when `qt6-base-dev`'s candidate
major.minor does not match the already-installed `libqt6core6t64`, so it will
not downgrade a newer desktop Qt.

| Path | Role |
| ---- | ---- |
| `~/.local/bin/monologue` | app (wrapper when Qt Multimedia QML is under `~/.local/lib/qt6/qml`) |
| `~/.local/share/applications/monologue.desktop` | launcher (`Exec` is the full path) |
| `~/.local/share/icons/hicolor/scalable/apps/monologue.svg` | icon |

Open **Monologue** from the launcher.

## Smoke check

1. Launch the app. The preview should show the camera; the meter should move when the mic is live.
2. Space starts a take; Space pauses; Enter opens the editor. Save writes an MP4 next to the chosen path.
3. Switch theme (`omarchy-theme-set …`). The accent should follow. Corners stay square on i3.

## Uninstall

```bash
rm -f ~/.local/bin/monologue ~/.local/libexec/monologue
rm -f ~/.local/share/applications/monologue.desktop
rm -f ~/.local/share/icons/hicolor/scalable/apps/monologue.svg
```

## License

MIT (upstream).