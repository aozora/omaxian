# Omaview (Omaxian port)

Omarchy's picture viewer and media player (launcher name: Media Viewer). Open
a photo, video, song, or a whole folder; step through with the arrows, zoom
with the wheel, scrub videos with a timeline, and put the chrome away with Tab.

Port of [omacom/omaview](https://github.com/omacom/omaview) (upstream commit
`4cd158e`, pinned in `.omaxian-upstream-commit`). Full upstream docs:
[`README.upstream.md`](README.upstream.md).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| Arch package / `omarchy-pkgs` | Debian `install.sh` → `~/.local` |
| Runtime dep `qt6-wayland` | Not installed. Uses XCB via `qt6-qpa-plugins` |
| Wayland idle-inhibit (`zwp_idle_inhibit` + GuiPrivate) | `org.freedesktop.ScreenSaver` over D-Bus, then `xdg-screensaver suspend` on the window XID (fits xss-lock) |
| `wl-copy` for clipboard after quit | Same on Wayland; on X11 uses `xclip` (Qt clipboard still used as last resort) |
| Hyprland window reshape + `hyprctl` corner radius | Unchanged; gated on `HYPRLAND_INSTANCE_SIGNATURE` (Qt resize + square corners on i3) |
| Theme / language from Omarchy paths | Unchanged — Omaxian writes the same files |
| CMake requires `wayland-client` / `wayland-protocols` | Dropped; CMake/qmake build without Wayland |
| CMake-only build | Same CMake path when `qt6-*-dev` works; `omaview.pro` + qmake fallback for `~/.local/opt/omaxian-qt6-<mm>/` |
| `VideoOutput.endOfStreamPolicy: KeepLastFrame` (Qt 6.9+) | Set from `Component.onCompleted` (through the item's id) only where the property exists; on Qt 6.8 the last frame already stays |
| `VideoOutput.clearOutput()` (Qt 6.9+) to drop the last file's frame | Called where it exists; the backend also hands the sink an empty frame, which clears it on Qt 6.8 |
| `QMediaPlayer` pitch compensation (Qt 6.10+) | Compiled in only against Qt ≥ 6.10. The pre-built binary targets Qt 6.8, so sped-up playback changes pitch |
| Cover art from `QMediaMetaData::CoverArtImage` | Falls back to `ThumbnailImage`, where Qt 6.8's FFmpeg backend puts an attached picture |
| Floating expected under Hyprland | i3 rule floats `omaview` (deployed `05_rules.conf`) |

## Requirements

- Qt 6 Quick / Controls / Multimedia (`qml6-module-qtmultimedia`)
- `ffmpeg` (and `ffprobe`)
- `xdg-desktop-portal` + GTK backend, `xdg-utils` (`xdg-screensaver`)
- `xclip` (clipboard persistence)
- Optional: `cups` (`lp` for print), `kimageformat6-plugins` (HEIC/AVIF/JXL), `wpctl` (volume above 100%)

Build: `cmake` + `qt6-base-dev` + `qt6-declarative-dev` + `qt6-multimedia-dev`,
or `qmake6` against `omaview.pro`. Stock Devuan Excalibur Qt 6.8 is enough.

## Install

```bash
community-apps/omaview/install.sh
```

With a pinned binary in `.omaxian-prebuilt`, `install.sh` downloads it
(sha256-checked, built against Qt 6.8 so it runs on 6.8 and newer) and
installs only the runtime packages. Otherwise, or with `--from-source`, it
builds as described below. See
[`../README.md`](../README.md#pre-built-binaries-omaxian-prebuilt).

`install.sh` refuses to apt-install Qt when the `qt6-base-dev` candidate's
major.minor does not match the already-installed `libqt6core6t64`.

| Path | Role |
| ---- | ---- |
| `~/.local/bin/omaview` | app (wrapper when QML modules live under `~/.local/lib/qt6/qml`) |
| `~/.local/libexec/omaview` | real binary when the wrapper is used |
| `~/.local/share/applications/omaview.desktop` | launcher + MIME handlers |
| `~/.local/share/icons/hicolor/scalable/apps/omaview.svg` | icon |

## Smoke check

1. `omaview some.jpg` opens the picture; arrows step through the folder.
2. `omaview some.mp4` plays; Space pauses; Tab hides chrome; screen stays awake while playing.
3. Ctrl+C copies a frame; after quit, paste still works if `xclip` is installed.
4. Theme switch updates colors; corners stay square on i3.

## Uninstall

```bash
rm -f ~/.local/bin/omaview ~/.local/libexec/omaview
rm -f ~/.local/share/applications/omaview.desktop
rm -f ~/.local/share/icons/hicolor/scalable/apps/omaview.svg
```

## License

MIT (upstream).
