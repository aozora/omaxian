# Omawrite (Omaxian port)

Markdown writing app with auto-save, find/replace, print, and Omarchy theme/language.

Port of [omacom/omawrite](https://github.com/omacom/omawrite) 0.7.5
(upstream commit `8ee488b`, pinned in `.omaxian-upstream-commit`). Full upstream
docs: [`README.upstream.md`](README.upstream.md).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| `omarchy pkg add omawrite` / Arch package | Debian `install.sh` → `~/.local` |
| Qt Quick Dialogs / Widgets / PrintSupport | Same; needs `qml6-module-qtquick-dialogs` at runtime |
| Theme from `colors.toml`; language from `~/.config/omarchy/language` | Unchanged |
| Bundled IBM Plex Mono | Unchanged (embedded via resources.qrc, SIL OFL) |
| Runtime dep `qt6-wayland` | Not installed. Uses XCB via `qt6-qpa-plugins` |
| CMake-only build | Same CMake path when `qt6-*-dev` works; `omawrite.pro` + qmake fallback for `~/.local/opt/omaxian-qt6-<mm>/` |

## Requirements

- Qt 6 Quick / Controls / Dialogs, Widgets, PrintSupport
- `xdg-desktop-portal` + GTK backend

Build: `cmake` + `qt6-base-dev` + `qt6-declarative-dev`, or `qmake6` against `omawrite.pro`.

## Install

```bash
community-apps/omawrite/install.sh
```

`install.sh` refuses to apt-install Qt when the `qt6-base-dev` candidate's
major.minor does not match the already-installed `libqt6core6t64`.

| Path | Role |
| ---- | ---- |
| `~/.local/bin/omawrite` | app (wrapper when QML modules live under `~/.local/lib/qt6/qml`) |
| `~/.local/libexec/omawrite` | real binary when the wrapper is used |
| `~/.local/share/applications/omawrite.desktop` | launcher |
| `~/.local/share/icons/hicolor/scalable/apps/omawrite.svg` | icon |

## Smoke check

1. `omawrite` opens an empty document.
2. Ctrl+S saves via the portal; Ctrl+O opens a Markdown file.
3. Theme switch updates the accent.

## Uninstall

```bash
rm -f ~/.local/bin/omawrite ~/.local/libexec/omawrite
rm -f ~/.local/share/applications/omawrite.desktop
rm -f ~/.local/share/icons/hicolor/scalable/apps/omawrite.svg
```

## License

MIT (upstream).
