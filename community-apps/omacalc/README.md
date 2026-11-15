# Omacalc (Omaxian port)

Dead-simple calculator that follows the Omarchy theme and text size.

Port of [omacom/omacalc](https://github.com/omacom/omacalc) 0.4.2
(upstream commit `e43fd0a`, pinned in `.omaxian-upstream-commit`). Full upstream
docs: [`README.upstream.md`](README.upstream.md).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| `omarchy pkg add omacalc` / Arch package | Debian `install.sh` → `~/.local` |
| Theme from `colors.toml` | Unchanged |
| Bundled iA Writer Mono | Unchanged (embedded via resources.qrc, SIL OFL) |
| Runtime dep `qt6-wayland` | Not installed. Uses XCB via `qt6-qpa-plugins` |
| CMake-only build | Same CMake path when `qt6-*-dev` works; `omacalc.pro` + qmake fallback for `~/.local/opt/omaxian-qt6-<mm>/` |

## Requirements

- Qt 6 Quick / Controls, `qt6-qpa-plugins`
- `xdg-desktop-portal` + GTK backend

Build: `cmake` + `qt6-base-dev` + `qt6-declarative-dev`, or `qmake6` against `omacalc.pro`.

## Install

```bash
community-apps/omacalc/install.sh
```

`install.sh` refuses to apt-install Qt when the `qt6-base-dev` candidate's
major.minor does not match the already-installed `libqt6core6t64`.

| Path | Role |
| ---- | ---- |
| `~/.local/bin/omacalc` | app |

| `~/.local/share/applications/omacalc.desktop` | launcher |
| `~/.local/share/icons/hicolor/scalable/apps/omacalc.svg` | icon |

## Smoke check

1. `omacalc` opens a keypad.
2. Enter `2×3+7`; result shows under the expression.
3. Theme switch updates the accent.

## Uninstall

```bash
rm -f ~/.local/bin/omacalc ~/.local/libexec/omacalc
rm -f ~/.local/share/applications/omacalc.desktop
rm -f ~/.local/share/icons/hicolor/scalable/apps/omacalc.svg
```

## License

MIT (upstream).
