# Checkmate (Omaxian port)

3D chess for Omarchy: play a friend on the same computer or the built-in
opponent, on four sculpted sets. Full upstream docs:
[`README.upstream.md`](README.upstream.md).

Port of [omacom/checkmate](https://github.com/omacom/checkmate) **0.1.2**
(upstream commit `2e69784`, full SHA in `.omaxian-upstream-commit`; version in
`.omaxian-upstream-version`).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| Arch package / `bin/build` pacman helpers | Debian `install.sh` → `~/.local` (apt); pacman block in `bin/build` is skipped when pacman is absent |
| Version from the release tarball or `git describe` | From `.omaxian-upstream-version` (`git describe` here would give Omaxian's tags) |
| Qt Test + `xvfb-run` required at CMake configure | Optional: the app builds without them; tests are added only when `libQt6Test` and `xvfb-run` are both present |
| `visible: parent.target` on the move marker | `visible: tile.target` (same behaviour; qmllint could not see the custom property through `parent`) |
| Runtime dep `qt6-wayland` | Not installed. Uses XCB via `qt6-qpa-plugins` |
| Popup corners from `hyprctl` rounding | Unchanged: without Hyprland, corners stay square on i3 |
| Theme and language from Omarchy paths | Unchanged — Omaxian writes the same files |

## Requirements

- Qt 6 Quick / Controls / Shapes / Quick 3D, Concurrent
- `qt6-qpa-plugins`, `qt6-svg-plugins`, `qt6-image-formats-plugins`
- OpenGL (`libgl1`, plus `libgl1-mesa-dri` / `mesa-libgallium` for software GL)
- `xdg-desktop-portal` + GTK backend

Build: `cmake` + `qt6-base-dev` + `qt6-declarative-dev` + `qt6-quick3d-dev`.
Stock Devuan Excalibur Qt 6.8 is enough. Tests (`bin/test`) also need `xvfb`,
`xauth`, and `fonts-dejavu-core`.

## Install

```bash
community-apps/checkmate/install.sh
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
| `~/.local/bin/checkmate` | app and headless commands |
| `~/.local/share/applications/checkmate.desktop` | launcher (`checkmate open`) |
| `~/.local/share/icons/hicolor/scalable/apps/checkmate.svg` | icon |

## Smoke check

1. Open Checkmate from the launcher; a board appears with Moss & Myth (or the last set).
2. New game → computer or two players; click a piece, then a highlighted square.
3. Right-drag orbits; scroll zooms; keys 1–4 switch sets; theme switch recolours the UI.
4. `checkmate --version` prints `Checkmate 0.1.2` without a display.

## License

MIT (upstream).
