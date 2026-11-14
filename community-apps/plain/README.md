# Plain (Omaxian port)

Qt Quick text editor for config files: one window, one file, conventional
keys (Ctrl+S / Z / F), Omarchy theme and language. Atomic saves, symlink-safe,
UTF-8 only.

Port of [omacom/plain](https://github.com/omacom/plain) 0.3.3
(upstream commit `9a24d38`, pinned in `.omaxian-upstream-commit`). Full upstream
docs: [`README.upstream.md`](README.upstream.md).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| `omarchy pkg add plain` / Arch package | Debian `install.sh` → `~/.local` |
| CMake-only build (`bin/build`) | Same CMake path when `qt6-*-dev` works; `plain.pro` + qmake fallback for the Monologue/Signed `~/.local/opt/omaxian-qt6-<mm>/` layout |
| Runtime dep `qt6-wayland` (typical Omarchy desktop) | Not installed. Uses XCB via `qt6-qpa-plugins` |
| `qml6-module-qtcore` (QtCore QML: StandardPaths / StandardKey) | Required. If apt cannot match libqt6core, stage under `~/.local/lib/qt6/qml/` and `install.sh` wraps the binary |
| Corner radius from `hyprctl` | Unchanged; already gated on `HYPRLAND_INSTANCE_SIGNATURE` (square corners on i3) |
| File chooser via xdg-desktop-portal | Same, with `xdg-desktop-portal-gtk` |
| Theme from `colors.toml`; text size from `shell.toml` `[font] base-size` | Unchanged — Omaxian Settings → Appearance writes the same paths |
| Language from `~/.config/omarchy/language` | Unchanged (`omarchy-language`) |

## Requirements

Runtime (also in `omaxian.deps.json`):

- Qt 6 Quick and Quick Controls (`qml6-module-qtquick*`), `qml6-module-qtcore`, `qt6-qpa-plugins`
- `xdg-desktop-portal` and `xdg-desktop-portal-gtk`

Build: `cmake` + `qt6-base-dev` + `qt6-declarative-dev`, or `qmake6` against
`plain.pro`. Stock Devuan Excalibur Qt 6.8 is enough (no Multimedia, no
Qt ≥ 6.9 pin like Hype).

## Install

```bash
community-apps/plain/install.sh
```

`install.sh` refuses to apt-install Qt when the `qt6-base-dev` candidate's
major.minor does not match the already-installed `libqt6core6t64`. If you keep
matching headers under `~/.local/opt/omaxian-qt6-<mm>/usr` (same layout as
Monologue/Signed), it uses that prefix via `CMAKE_PREFIX_PATH`.

| Path | Role |
| ---- | ---- |
| `~/.local/bin/plain` | app (wrapper when QtCore QML is under `~/.local/lib/qt6/qml`) |
| `~/.local/libexec/plain` | real binary when the wrapper is used |
| `~/.local/share/applications/plain.desktop` | launcher (`Exec` is the full path) |
| `~/.local/share/icons/hicolor/scalable/apps/plain.svg` | icon |

Open **Text Editor** from the launcher, or `plain path/to/file`. Works as
`$EDITOR` / `$VISUAL` / `$SUDO_EDITOR` (foreground until the window closes).

After install, make it the desktop default (config menu, MIME, `$EDITOR`):

```bash
omarchy-default-editor plain
```

That is also the unread default when nothing is saved under
`~/.local/state/omarchy/defaults/editor` (falls back to Neovim if `plain` is
missing). Setup → Default → Editor lists Plain first.

## Smoke check

1. `plain --version` prints a version without needing a display.
2. `plain /tmp/plain-smoke.txt` opens a window; Ctrl+S writes the file; Ctrl+W closes.
3. Switch theme (`omarchy-theme-set …`). The accent should follow. Corners stay square on i3.
4. Ctrl+O / Ctrl+Shift+S need a working xdg-desktop-portal (GTK backend).

## Uninstall

```bash
rm -f ~/.local/bin/plain
rm -f ~/.local/share/applications/plain.desktop
rm -f ~/.local/share/icons/hicolor/scalable/apps/plain.svg
```

Settings in `~/.config/plain/` are left alone.

## License

MIT (upstream).
