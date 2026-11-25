# Cards (Omaxian port)

Klondike solitaire for Omarchy: draw three, no limit on passes, in four card
series. Full upstream docs: [`README.upstream.md`](README.upstream.md).

Port of [omacom/cards](https://github.com/omacom/cards) **0.1.0** plus the
papercraft icon update (upstream commit `e1a01bf`, full SHA in
`.omaxian-upstream-commit`; version in `.omaxian-upstream-version`).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| Arch package / `omarchy pkg add` | Debian `install.sh` → `~/.local` |
| Qt Test required at CMake configure | Optional: the app builds without it; tests are added only when `libQt6Test` is present |
| Runtime dep `qt6-wayland` | Not installed. Uses XCB via `qt6-qpa-plugins` |
| Popup corners from `hyprctl` rounding | Unchanged: without Hyprland, corners stay square on i3 |
| Theme and language from Omarchy paths | Unchanged — Omaxian writes the same files |

## Requirements

- Qt 6 Quick / Controls / Shapes, `qt6-qpa-plugins`, `qt6-svg-plugins`
- `xdg-desktop-portal` + GTK backend

Build: `cmake` + `qt6-base-dev` + `qt6-declarative-dev`. Stock Devuan
Excalibur Qt 6.8 is enough.

## Install

```bash
community-apps/cards/install.sh
```

With a pinned binary in `.omaxian-prebuilt`, `install.sh` downloads it
(sha256-checked, built against Qt 6.8 so it runs on 6.8 and newer) and
installs only the runtime packages. Otherwise, or with `--from-source`, it
builds with `bin/build`. See
[`../README.md`](../README.md#pre-built-binaries-omaxian-prebuilt).

`install.sh` refuses to apt-install Qt when the `qt6-base-dev` candidate's
major.minor does not match the already-installed `libqt6core6t64`.

| Path | Role |
| ---- | ---- |
| `~/.local/bin/cards` | app and headless commands |
| `~/.local/share/applications/cards.desktop` | launcher (`cards open`) |
| `~/.local/share/icons/hicolor/scalable/apps/cards.svg` | icon |

## Smoke check

1. Open Cards from the launcher; a deal appears in the Phosphor series.
2. Click or drag a card; double-click sends it home when legal; `N` deals again.
3. Switch the Omarchy theme; Phosphor recolours with it.
4. Keys 1–4 change series; `?` shows shortcuts.

## License

MIT (upstream).
