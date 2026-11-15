# Omacut (Omaxian port)

Open a video, trim/split/reorder clips, preview, and export MP4 via ffmpeg.

Port of [omacom/omacut](https://github.com/omacom/omacut) 0.8.3
(upstream commit `fc452f1`, pinned in `.omaxian-upstream-commit`). Full upstream
docs: [`README.upstream.md`](README.upstream.md).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| `omarchy pkg add omacut` / Arch package | Debian `install.sh` → `~/.local` |
| Corner radius from `hyprctl` | Unchanged; gated on `HYPRLAND_INSTANCE_SIGNATURE` (square on i3) |
| `ffmpeg` / `ffprobe` | Same (`ffmpeg` package) |
| Qt Multimedia QML | Required; wrap via `~/.local/lib/qt6/qml` when apt cannot match libqt6core |
| Theme accent from `colors.toml` | Unchanged |
| Runtime dep `qt6-wayland` | Not installed. Uses XCB via `qt6-qpa-plugins` |
| CMake-only build | Same CMake path when `qt6-*-dev` works; `omacut.pro` + qmake fallback for `~/.local/opt/omaxian-qt6-<mm>/` |

## Requirements

- Qt 6 Quick / Controls / Multimedia (`qml6-module-qtmultimedia`)
- `ffmpeg` (and `ffprobe`)
- `xdg-desktop-portal` + GTK backend

Build: `cmake` + `qt6-base-dev` + `qt6-declarative-dev` + `qt6-multimedia-dev`, or `qmake6` against `omacut.pro`.

## Install

```bash
community-apps/omacut/install.sh
```

`install.sh` refuses to apt-install Qt when the `qt6-base-dev` candidate's
major.minor does not match the already-installed `libqt6core6t64`.

| Path | Role |
| ---- | ---- |
| `~/.local/bin/omacut` | app (wrapper when QML modules live under `~/.local/lib/qt6/qml`) |
| `~/.local/libexec/omacut` | real binary when the wrapper is used |
| `~/.local/share/applications/omacut.desktop` | launcher |
| `~/.local/share/icons/hicolor/scalable/apps/omacut.svg` | icon |

## Smoke check

1. `omacut some.mp4` opens the timeline.
2. Trim a handle, Space to preview, Ctrl+S to export.
3. Theme switch updates the accent; corners stay square on i3.

## Uninstall

```bash
rm -f ~/.local/bin/omacut ~/.local/libexec/omacut
rm -f ~/.local/share/applications/omacut.desktop
rm -f ~/.local/share/icons/hicolor/scalable/apps/omacut.svg
```

## License

MIT (upstream).
