# Omawrite (Omaxian port)

Markdown writing app with auto-save, find/replace, print, and Omarchy theme/language.

Port of [omacom/omawrite](https://github.com/omacom/omawrite) 0.7.8
(upstream commit `1c09d42`, pinned in `.omaxian-upstream-commit`). Full upstream
docs: [`README.upstream.md`](README.upstream.md).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| `omarchy pkg add omawrite` / Arch package | Debian `install.sh` → `~/.local` |
| Portal file chooser / Widgets / PrintSupport | Same; needs `xdg-desktop-portal` and the GTK backend |
| Theme from `colors.toml`; language from `~/.config/omarchy/language` | Unchanged |
| Bundled IBM Plex Mono | Unchanged (embedded via resources.qrc, SIL OFL) |
| Runtime dep `qt6-wayland` | Not installed. Uses XCB via `qt6-qpa-plugins` |
| CMake-only build | Same CMake path when `qt6-*-dev` works; `omawrite.pro` + qmake fallback for `~/.local/opt/omaxian-qt6-<mm>/` |
| CMake requires `GuiPrivate` (Qt 6.9+ package) for the tests | Not required: Debian's Qt 6.8 has no `Qt6GuiPrivate` package. `omawrite_tests` builds only when `qt6-base-private-dev` is installed; the app never needs it |

## Requirements

- Qt 6 Quick / Controls, Widgets, PrintSupport
- `xdg-desktop-portal` + GTK backend

Build: `cmake` + `qt6-base-dev` + `qt6-declarative-dev`, or `qmake6` against `omawrite.pro`.

## Install

```bash
community-apps/omawrite/install.sh
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
| `~/.local/bin/omawrite` | app |
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
