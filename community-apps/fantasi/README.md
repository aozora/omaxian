# Fantasi (Omaxian port)

Make images, video clips and songs on your own machine with Omarchy's local AI
models. Full upstream docs: [`README.upstream.md`](README.upstream.md).

Port of [omacom/fantasi](https://github.com/omacom/fantasi) **0.3.0**
(upstream commit in `.omaxian-upstream-commit`, version in
`.omaxian-upstream-version`).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| Arch package / `omarchy pkg add` | Debian `install.sh` → `~/.local` |
| Models from `omarchy-models` (Podman Quadlets under systemd) | The same command, from the systemd-free engine in [`../omarchy-local-ai/`](../omarchy-local-ai/). Install that first. Only the music model (ACE-Step) has been run; image and video models are untested |
| Runtime dep `qt6-wayland` | Not installed. Uses XCB via `qt6-qpa-plugins` |
| A second `fantasi` brings the open window forward with `omarchy-launch-or-focus` (Hyprland) | `i3-msg '[class="(?i)^fantasi$"] focus'` |
| Image size follows the focused monitor from `hyprctl` | Skipped without Hyprland, so the default 1344×768 target is used |
| Corner rounding from `hyprctl` | Unchanged: gated on `HYPRLAND_INSTANCE_SIGNATURE`, so corners stay square on i3 |
| Hints and the agent skill say `omarchy models start …` / `use …` | `omarchy-models start …` / `use …` (there is no `omarchy` dispatcher) |
| Theme and language from Omarchy paths | Unchanged — Omaxian writes the same files |
| `const long` / `const short` in `SongPlayer.qml` (reserved words in Qt 6.8's JS engine) | Renamed `slowWave` / `quickWave` |
| `Application.styleHints.accessibility.motionPreference` (Qt 6.10+) | Read only when `accessibility` exists; on 6.8 the wave always moves |
| `contentItem.forceActiveFocus()` takes the focus out of the prompt | On Qt 6.8 it stays in the prompt's `ScrollView` scope, so F, Delete and the arrows never reached their shortcuts. `releasePrompt()` clears the prompt's focus first (same on newer Qt) |
| `find_package(Qt6 … Test …)` is required at configure time | Probed first and optional, as in `cards` |
| Tests need `ffmpeg`, `imagemagick`, a session bus, and a non-root user (one test makes a folder read-only) | Same; run them under `dbus-run-session` as a normal user |

Verified on Qt 6.8 (Debian trixie container): builds, `lib/qmllint-qt68.sh
fantasi` is clean, and the upstream tests pass.

## Requirements

- Qt 6 Quick / Controls (Material) / Effects / Shapes / Multimedia / DBus /
  Concurrent, `qt6-qpa-plugins`, `qt6-svg-plugins`
- The local model engine: `community-apps/omarchy-local-ai/install.sh`
  (rootless Podman). Without it the app shows its set-up screen.
- `omarchy-models` on `PATH` (`~/.local/bin`)
- `xdg-desktop-portal` + a backend (GTK) for "add a picture"

Build: `cmake` + `qt6-base-dev` + `qt6-declarative-dev` +
`qt6-multimedia-dev` + `qt6-shadertools-dev`.

## Install

```bash
community-apps/omarchy-local-ai/install.sh   # the engine, once
community-apps/fantasi/install.sh
```

There is no pinned pre-built binary yet, so `install.sh` builds with
`bin/build`. When the local Qt (`~/.local/opt/omaxian-qt6-<mm>`) has no
ShaderTools it builds against Qt 6.8 in a `debian:trixie` container (podman or
docker) instead; that binary runs on 6.8 and newer. When QtCore, QtMultimedia
or Effects exist only under `~/.local/lib/qt6/qml`, it installs a wrapper that
points at them, as Folio does. See
[`../README.md`](../README.md#pre-built-binaries-omaxian-prebuilt).

| Path | Role |
| ---- | ---- |
| `~/.local/bin/fantasi` | app |
| `~/.local/share/applications/fantasi.desktop` | launcher |
| `~/.local/share/icons/hicolor/scalable/apps/fantasi.svg` | icon |

## Smoke check

1. `fantasi` opens the window. With no model running it offers to set one up.
2. With a music model running: `fantasi generate --music "warm lo-fi" --instrumental`
   prints the path of an MP3 under `~/Music/Generated`.
3. A second `fantasi` brings the open window to the front.
4. Switch theme (`omarchy-theme-set …`): the accent follows.

## Uninstall

```bash
rm -f ~/.local/bin/fantasi ~/.local/libexec/fantasi
rm -f ~/.local/share/applications/fantasi.desktop
rm -f ~/.local/share/icons/hicolor/scalable/apps/fantasi.svg
```

## License

MIT (upstream).
