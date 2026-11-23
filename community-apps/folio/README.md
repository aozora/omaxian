# Folio (Omaxian port)

Omarchy's file manager: columns / list tree / grid, Space previews, trash, drives,
and keyboard-first browsing that follows the Omarchy theme and the system's
monospace font. Can also be other
apps' Open and Save dialogs via `folio chooser` (xdg-desktop-portal).

Port of [omacom/folio](https://github.com/omacom/folio) (upstream commit
`f73d8e4`, v0.7.2, pinned in `.omaxian-upstream-commit`). Full upstream docs:
[`README.upstream.md`](README.upstream.md).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| Arch package / `omarchy-pkgs` | Debian `install.sh` → `~/.local` |
| Runtime dep `qt6-wayland` | Not installed. Uses XCB via `qt6-qpa-plugins` |
| Plugins under `/usr/share/folio/plugins` (`FOLIO_PACKAGED_PLUGINS`, from the CMake install prefix) | `~/.local/share/folio/plugins`, which Folio reads as well. The build keeps upstream's `/usr` default; `folio.pro` defines the same path |
| `cmake --install` lays out the package | Not used. `install.sh` copies the files into `~/.local` and rewrites the `Exec=` paths |
| `org.freedesktop.FileManager1.service` starts Folio for other apps' "Show in folder" | Shipped in `share/` but not installed, so Folio doesn't take that over from the file manager you already use. Opt in below |
| Portal/DBus under `/usr/share/…` with `Exec=/usr/bin/folio` | `~/.local/share/xdg-desktop-portal/portals/` + `~/.local/share/dbus-1/services/` with `Exec=~/.local/bin/folio` |
| `hyprland-portals.conf` + `systemctl --user restart` | Document `~/.config/xdg-desktop-portal/portals.conf` (XDG desktop `i3`); restart portal however the host runs it |
| Corner radius from `hyprctl` | Unchanged; gated on `HYPRLAND_INSTANCE_SIGNATURE` (square on i3) |
| Theme / language from Omarchy paths | Unchanged — Omaxian writes the same files |
| Font and text size follow the system's fixed-width font (13px text at Omarchy's 11pt default) | Unchanged. The family is what `fc-match monospace` names. Omaxian sets no Qt font size, so Qt reports 9pt without a platform theme (11px text) and GTK's 10pt under `QT_QPA_PLATFORMTHEME=gtk3` (12px text) |
| `xdg-terminal-exec` for Open Terminal | Same; Excalibur ships it |
| Preview PDF error text names Arch `qt6-webengine` | Debian package is `qml6-module-qtquick-pdf` |
| CMake-only build | Same CMake path when `qt6-*-dev` works; `folio.pro` + qmake fallback for `~/.local/opt/omaxian-qt6-<mm>/` (keep its sources and `fontconfig` in step with `CMakeLists.txt`) |
| Preview `setDesktopFileName("folio-preview")` only | Also `setApplicationName("folio-preview")` so i3 can float Space preview on X11 |
| Chooser `setDesktopFileName("folio-chooser")` only | Also `setApplicationName("folio-chooser")`; i3 floats/centers `folio-chooser` |
| Plugin dirs may be group-writable from umask | `install.sh` runs `chmod -R go-w` so Folio's `trusted()` accepts them |
| `QDir::mkpath(path, permissions)` for the home trash (Qt 6.10+) | `mkpathWith()` in `src/fileops.cpp`: the same call on Qt ≥ 6.10, per-level `QDir::mkdir(path, permissions)` on Excalibur's Qt 6.8 |
| Views set `acceptedButtons: Qt.NoButton` (`Flickable` property, Qt 6.9+) | Set from `Component.onCompleted` only where the property exists (`FileListView`, grid, columns flick). On Qt 6.8 the rubber band (`Band.qml`) sets `preventStealing`, so a drag on empty space draws the band instead of flicking. Dragging a file away isn't covered by a test on 6.8 |
| `Band.qml` declared inside a `GridView` / `ListView` (stays on the view, not its content) | Band reparented to `view.contentItem`, so a press on empty space after scrolling starts a band rather than counting as a press on a tile. Upstream bug on every Qt; `gridBandDragDoesNotFlick` covers it |
| Tests use `QQmlPropertyMap::create()` and a `QPointF` `QDragEnterEvent` (newer Qt) | `tests/folio_tests.cpp` uses `new QQmlPropertyMap` and `toPoint()`, so the tests compile on Qt 6.8 |

## Requirements

Runtime (also in `omaxian.deps.json`):

- Qt 6 Quick / Controls / Effects / Shapes / QtCore QML, `qt6-qpa-plugins`
- `gvfs` + `gvfs-backends`, `udisks2`, `libarchive-tools` (`bsdtar`: compress,
  extract, and the names inside an archive in its preview)
- `xdg-terminal-exec`, `xdg-desktop-portal` + GTK backend
- Optional Space preview: `qml6-module-qtmultimedia`, `qml6-module-qtquick-pdf`
- Optional thumbs: `poppler-utils`, `ffmpegthumbnailer`, `heif-thumbnailer`
  (HEIC / AVIF pictures: Qt has no decoder for them, so their thumbnails and
  Space preview both come from this thumbnailer)

Build: `cmake` + `qt6-base-dev` + `qt6-declarative-dev` + `libglib2.0-dev` +
`libfontconfig-dev` + `zlib1g-dev`, or `qmake6` against `folio.pro`. Stock Devuan Excalibur Qt 6.8 is
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
via `CMAKE_PREFIX_PATH` and skips Qt runtime packages (QML modules,
`qt6-qpa-plugins`, `qt6-svg-plugins`) whose apt candidate is a different Qt.

| Path | Role |
| ---- | ---- |
| `~/.local/bin/folio` | app (wrapper when QML modules live under `~/.local/lib/qt6/qml`) |
| `~/.local/libexec/folio` | real binary when the wrapper is used |
| `~/.local/share/applications/folio.desktop` | launcher (`inode/directory`) |
| `~/.local/share/applications/folio-chooser.desktop` | Open/Save dialog process (`NoDisplay`) |
| `~/.local/share/xdg-desktop-portal/portals/folio.portal` | portal impl declaration |
| `~/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.folio.service` | D-Bus activation for `folio chooser` |
| `~/.local/share/icons/hicolor/scalable/apps/folio.svg` | icon |
| `~/.local/share/folio/plugins/` | Dropbox / LocalSend / Tailscale plugins |

Make Folio the default folder handler (also used by `omarchy-launch-files` /
Super+Shift+F):

```bash
xdg-mime default folio.desktop inode/directory
```

Or set `OMARCHY_FILE_MANAGER=folio`.

### Open / Save dialogs (optional)

`install.sh` installs the portal and D-Bus files; it does **not** change your
portal preference. To prefer Folio for FileChooser, edit
`~/.config/xdg-desktop-portal/portals.conf`:

```ini
[preferred]
org.freedesktop.impl.portal.FileChooser=folio;gtk;
```

Then restart the portal (`killall xdg-desktop-portal` and open a dialog, or
whatever your host uses — there is no systemd user session on Devuan). i3
floats and centers `folio-chooser` windows (deployed `05_rules.conf`).

### "Show in folder" from other apps (optional)

A running Folio already answers `org.freedesktop.FileManager1`. To have D-Bus
start it when no file manager is running (this replaces whichever file manager
answered before):

```bash
sed "s|^Exec=/usr/bin/folio|Exec=$HOME/.local/bin/folio|" \
  community-apps/folio/share/org.freedesktop.FileManager1.service \
  > ~/.local/share/dbus-1/services/org.freedesktop.FileManager1.service
```

## Smoke check

1. `folio --help` / opening `folio` shows a window on the home folder.
2. Ctrl+1/2/3 switches columns / list / grid; Space opens a preview.
3. Switch theme (`omarchy-theme-set …`). The accent should follow. Corners stay square on i3.
   Text is in the font `fc-match monospace` names.
4. Delete a file → Trash; restore from the sidebar Trash place.
5. Open Terminal on a folder needs `xdg-terminal-exec` on PATH.
6. With FileChooser=folio enabled: an app's Open/Save dialog is a Folio window
   (`folio-chooser` class), floated and centered.

## Uninstall

```bash
rm -f ~/.local/bin/folio ~/.local/libexec/folio
rm -f ~/.local/share/applications/folio.desktop
rm -f ~/.local/share/applications/folio-chooser.desktop
rm -f ~/.local/share/icons/hicolor/scalable/apps/folio.svg
rm -f ~/.local/share/xdg-desktop-portal/portals/folio.portal
rm -f ~/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.folio.service
rm -f ~/.local/share/dbus-1/services/org.freedesktop.FileManager1.service  # only if it is Folio's
rm -rf ~/.local/share/folio
```

## License

MIT (upstream).
