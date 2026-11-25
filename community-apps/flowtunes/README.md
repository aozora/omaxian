# Flowtunes (Omaxian port)

Endless music in the genre you pick, made on your own machine by Omarchy's
local music model (ACE-Step). Full upstream docs:
[`README.upstream.md`](README.upstream.md).

Port of [omacom/flowtunes](https://github.com/omacom/flowtunes) **0.4.0**
(upstream commit in `.omaxian-upstream-commit`, version in
`.omaxian-upstream-version`).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| Arch package / `omarchy pkg add` | Debian `install.sh` → `~/.local` |
| Music from `omarchy-agent-local` (Podman Quadlets under systemd) | The same command, from the systemd-free engine in [`../omarchy-local-ai/`](../omarchy-local-ai/). Install that first |
| Runtime dep `qt6-wayland` | Not installed. Uses XCB via `qt6-qpa-plugins` |
| Window matched by Wayland `app_id` | On X11 the window class is `flowtunes` (Qt's application name), which is what `StartupWMClass` names |
| Corner rounding from `hyprctl` | Unchanged: gated on `HYPRLAND_INSTANCE_SIGNATURE`, so corners stay square on i3 |
| Theme and language from Omarchy paths | Unchanged — Omaxian writes the same files |
| MPRIS on the session bus | Unchanged. Needs a session D-Bus (the X session has one) |
| `const long` / `const short` in `Wave.qml` (a reserved word to Qt 6.8's JS engine, so `Wave` failed to load) | Renamed `slowWave` / `quickWave` |
| `Application.styleHints.accessibility.motionPreference` (Qt 6.10+) | Read only when `accessibility` exists; on 6.8 the wave always moves |
| `find_package(Qt6 … Test …)` is required at configure time | Test is probed first and optional, as in `cards`: an incomplete local Qt overlay has `Qt6TestConfig.cmake` without the library, which made the configure fail |
| Tests need `ffmpeg` (they render a one-second MP3) and, for the MPRIS test, a session bus | Same; run them under `dbus-run-session` |

Apart from the two QML fixes, the app is unchanged: it only runs `omarchy-agent-local` (`refresh --quiet`,
`start`, `stop`, `use --detach`) and watches its `status.json` / `list.json`.

Verified on Qt 6.8 (Debian trixie container): builds, `lib/qmllint-qt68.sh flowtunes` is clean, and the upstream tests pass (`ffmpeg`, `dbus-run-session`). Also run on this desktop (Qt 6.10 runtime) against the real model: `flowtunes jazz` rendered a 2:59 tune in about 2m15s, saved it under `~/Music/Jazz/` and played it.

## Requirements

- Qt 6 Quick / Controls (Material) / Layouts / Multimedia / DBus,
  `qt6-qpa-plugins`, `qt6-svg-plugins`
- The local model engine: `community-apps/omarchy-local-ai/install.sh`
  (rootless Podman; ACE-Step is about 7.6 GiB of weights). Without it the
  app shows its set-up screen.
- `omarchy-agent-local` on `PATH` (`~/.local/bin`)
- Audio via PulseAudio or PipeWire

Build: `cmake` + `qt6-base-dev` + `qt6-declarative-dev` +
`qt6-multimedia-dev` + `qt6-shadertools-dev`. Stock Devuan Excalibur Qt 6.8 is
enough.

## Install

```bash
community-apps/omarchy-local-ai/install.sh   # the engine, once
community-apps/flowtunes/install.sh
```

CI builds the pre-built binary (`.github/workflows/community-apps.yml`); until its pin
lands, `install.sh` builds with `bin/build`. When the local Qt (`~/.local/opt/omaxian-qt6-<mm>`) has no
ShaderTools, which apt cannot supply for Qt 6.10, it builds against Qt 6.8 in a
`debian:trixie` container (podman or docker) instead. That binary runs on 6.8
and newer. When QtMultimedia exists only under `~/.local/lib/qt6/qml`, it
installs a wrapper that points at it, as Folio does. See [`../README.md`](../README.md#pre-built-binaries-omaxian-prebuilt).

| Path | Role |
| ---- | ---- |
| `~/.local/bin/flowtunes` | app |
| `~/.local/share/applications/flowtunes.desktop` | launcher |
| `~/.local/share/icons/hicolor/scalable/apps/flowtunes.svg` | icon |

## Smoke check

1. `flowtunes` shows the genre picker; `flowtunes jazz` starts a genre.
2. With no model set up, it offers to set up ACE-Step (about 7.6 GiB).
3. Once the model runs, the first tune is made and plays; the next two are
   prepared behind it. Space pauses, N skips.
4. `playerctl status` reports it, and the media keys work.
5. Switch theme (`omarchy-theme-set …`): the accent follows.
6. Tunes are saved as MP3 under `~/Music/<Genre>/`.

## Uninstall

```bash
rm -f ~/.local/bin/flowtunes
rm -f ~/.local/share/applications/flowtunes.desktop
rm -f ~/.local/share/icons/hicolor/scalable/apps/flowtunes.svg
```

## License

MIT (upstream).
