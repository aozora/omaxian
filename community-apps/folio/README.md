# Folio (Omaxian port)

Omarchy's file manager: grid / list / columns, Space previews, trash, drives,
and keyboard-first browsing that follows the Omarchy theme.

Port of [omacom/folio](https://github.com/omacom/folio) (upstream commit
`61b7e20`, pinned in `.omaxian-upstream-commit`). Full upstream docs:
[`README.upstream.md`](README.upstream.md).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| Arch package / `omarchy-pkgs` | Debian `install.sh` → `~/.local` |
| Runtime dep `qt6-wayland` | Not installed. Uses XCB via `qt6-qpa-plugins` |
| Plugins under `/usr/share/folio/plugins` | `~/.local/share/folio/plugins` |
| Corner radius from `hyprctl` | Unchanged; gated on `HYPRLAND_INSTANCE_SIGNATURE` (square on i3) |
| Theme / language from Omarchy paths | Unchanged — Omaxian writes the same files |
| `xdg-terminal-exec` for Open Terminal | Same; Excalibur ships it |
| Preview PDF error text names Arch `qt6-webengine` | Debian package is `qml6-module-qtquick-pdf` |
| CMake-only build | Same CMake path when `qt6-*-dev` works; `folio.pro` + qmake fallback for `~/.local/opt/omaxian-qt6-<mm>/` |
| Preview `setDesktopFileName("folio-preview")` only | Also `setApplicationName("folio-preview")` so i3 can float Space preview on X11 |
| Plugin dirs may be group-writable from umask | `install.sh` runs `chmod -R go-w` so Folio's `trusted()` accepts them |
| `QDir::mkpath(path, permissions)` for the home trash (Qt 6.10+) | `mkpathWith()` in `src/fileops.cpp`: the same call on Qt ≥ 6.10, per-level `QDir::mkdir(path, permissions)` on Excalibur's Qt 6.8 |
| Tests use `QQmlPropertyMap::create()` and a `QPointF` `QDragEnterEvent` (newer Qt) | `tests/folio_tests.cpp` uses `new QQmlPropertyMap` and `toPoint()`, so the tests compile on Qt 6.8 |

## Requirements

Runtime (also in `omaxian.deps.json`):

- Qt 6 Quick / Controls / Effects / Shapes / QtCore QML, `qt6-qpa-plugins`
- `gvfs` + `gvfs-backends`, `udisks2`, `libarchive-tools` (`bsdtar`)
- `xdg-terminal-exec`, `xdg-desktop-portal` + GTK backend
- Optional Space preview: `qml6-module-qtmultimedia`, `qml6-module-qtquick-pdf`
- Optional thumbs: `poppler-utils`, `ffmpegthumbnailer`

Build: `cmake` + `qt6-base-dev` + `qt6-declarative-dev` + `libglib2.0-dev` +
`zlib1g-dev`, or `qmake6` against `folio.pro`. Stock Devuan Excalibur Qt 6.8 is
enough.

Bundled plugins (Dropbox, LocalSend, Tailscale) soft-fail when those binaries
are missing.

## Install

```bash
community-apps/folio/install.sh
```

With a pinned binary in `.omaxian-prebuilt`, `install.sh` downloads it
(sha256-checked, built against Qt 6.8 so it runs on 6.8 and newer) and
installs only the runtime packages. Otherwise, or with `--from-source`, it
builds as described below. See
[`../README.md`](../README.md#pre-built-binaries-omaxian-prebuilt).

`install.sh` refuses to apt-install Qt when the `qt6-base-dev` candidate's
major.minor does not match the already-installed `libqt6core6t64`. If you keep
matching headers under `~/.local/opt/omaxian-qt6-<mm>/usr`, it uses that prefix
via `CMAKE_PREFIX_PATH`.

| Path | Role |
| ---- | ---- |
| `~/.local/bin/folio` | app (wrapper when QML modules live under `~/.local/lib/qt6/qml`) |
| `~/.local/libexec/folio` | real binary when the wrapper is used |
| `~/.local/share/applications/folio.desktop` | launcher (`inode/directory`) |
| `~/.local/share/icons/hicolor/scalable/apps/folio.svg` | icon |
| `~/.local/share/folio/plugins/` | Dropbox / LocalSend / Tailscale plugins |

Make Folio the default folder handler (also used by `omarchy-launch-files` /
Super+Shift+F):

```bash
xdg-mime default folio.desktop inode/directory
```

Or set `OMARCHY_FILE_MANAGER=folio`.

## Smoke check

1. `folio --help` / opening `folio` shows a window on the home folder.
2. Ctrl+1/2/3 switches grid / list / columns; Space opens a preview.
3. Switch theme (`omarchy-theme-set …`). The accent should follow. Corners stay square on i3.
4. Delete a file → Trash; restore from the sidebar Trash place.
5. Open Terminal on a folder needs `xdg-terminal-exec` on PATH.

## Uninstall

```bash
rm -f ~/.local/bin/folio ~/.local/libexec/folio
rm -f ~/.local/share/applications/folio.desktop
rm -f ~/.local/share/icons/hicolor/scalable/apps/folio.svg
rm -rf ~/.local/share/folio
```

## License

MIT (upstream).
