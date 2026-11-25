# Omareel (Omaxian port)

Screen recorder and editor: records the screen without the cursor, records the pointer, clicks
and keys separately, then renders a smooth synthetic cursor, click rings, padded and rounded
framing on a background, and auto zooms that follow the cursor. Exports MP4 or GIF. Full
upstream docs: [`README.upstream.md`](README.upstream.md) and [`docs/USAGE.md`](docs/USAGE.md).

Port of [omacom/omareel](https://github.com/omacom/omareel) **0.5.0** (upstream commit in
`.omaxian-upstream-commit`, version in `.omaxian-upstream-version`).

This is a **standalone app**, not a Quickshell plugin. It lives under `community-apps/` so
`./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

Upstream asks Hyprland for monitors, keyboards and the pointer, captures through a Wayland
protocol, and keeps its overlays out of the video with a Hyprland plugin. Without
`HYPRLAND_INSTANCE_SIGNATURE` the port answers those from X11 and i3 instead, mostly in
[`crates/omareel_record/src/x11.rs`](crates/omareel_record/src/x11.rs); the Hyprland paths are
left as they are. Every change is marked `Omaxian:` in the source.

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| Arch package / `omarchy-pkg-add omareel` | Debian `install.sh` → `~/.local` |
| Rust from Arch (`rust`, `corrosion`) | rustup, pinned in `rust-toolchain.toml` (Debian's rustc 1.85 is older than the crates' 1.86). `bin/build` points Debian's Corrosion 0.5 at rustup's `rustc`/`cargo`, since it cannot read newer rustup's toolchain list |
| Screen capture in process (`ext-image-copy-capture-v1`), gpu-screen-recorder as fallback | gpu-screen-recorder only (`-cursor no`). When it is not on `PATH`, `omareel __record-gsr` runs Omaxian's Flatpak wrapper `omarchy-gpu-screen-recorder` and passes SIGINT/SIGTERM on to the sandboxed recorder ([`src/GsrShim.h`](src/GsrShim.h)): signalled directly, bwrap dies and leaves the recorder running with an unfinished file |
| Monitors from `hyprctl -j monitors` | `xrandr --listactivemonitors`; the focused one and the space bars reserve from `i3-msg -t get_workspaces`, printed in hyprctl's shape so upstream's parsers read them unchanged |
| Pointer from a Wayland cursor session or Hyprland IPC | `XQueryPointer`, once per captured frame, on the sampler's own display connection |
| Key names from `hyprctl devices -j`, layout switches followed | `setxkbmap -query` (rules, model, layout, variant, options). Switches during a recording are not followed; the first layout names the keys |
| Region / window pick: `omarchy-capture-region smart` or `slurp` fed window rectangles | Omaxian's `omarchy-capture-region` (slop) for both: a drag picks a region, a click picks the window under it. A click on the desktop (slop returns the whole X screen) records the monitor under the pointer |
| Recording bar, countdown and camera bubble are layer-shell surfaces | Override-redirect X11 windows that never take focus, placed where the layer-shell anchors would put them ([`src/ui/OverlayCompat.h`](src/ui/OverlayCompat.h)). LayerShellQt is an off-by-default build option (`OMAREEL_LAYER_SHELL`); without it a no-op stand-in takes its calls, so neither the build nor the binary needs it |
| Hyprland plugin keeps the overlays out of the capture | Not available on X11. With two monitors the overlays go to the other one (upstream's fallback); with one they stay hidden while recording, so stop with a keybind or `omareel record --stop` |
| `cursor:no_hardware_cursors` held while recording | Not needed: gpu-screen-recorder leaves the X cursor out |
| Layer rules through `hyprctl` | Skipped |
| `find_package(Qt6 … GuiPrivate …)` | Asked for only on Qt 6.9+; Qt 6.8 provides `Qt6::GuiPrivate` through `Gui` |
| LayerShellQt 6.4 API (`setScreen`, `screen`, `setActivateOnShow`) | Used only with LayerShellQt 6.4+ (trixie has 6.3) |
| Corner rounding from `hyprctl getoption decoration:rounding` | Unchanged: without hyprctl the theme's default is used |
| Hyprland plugin (`plugin/`), golden test corpus (`tests/golden`, 19 MB) and its generator (`tools/`), Arch packaging, upstream CI | Not vendored. The crates' unit tests and the C++ tests (`tests/*.cpp`, `tests/fixtures/synthetic`) are kept |

The editor and exporter are unchanged.

## Verified

- Builds against Qt 6.8 in a `debian:trixie` container; all 216 Rust unit tests pass (`cargo test --workspace --exclude omareel_qt --lib`), including the X11 ones.
- `lib/qmllint-qt68.sh omareel` is clean (modules from `.qmllint-modules`; `FrameSource` false positives in `lib/qmllint-ignore.txt`).
- On this desktop (i3, Qt 6.10 runtime, Flatpak gpu-screen-recorder 6.1.7, one 2560×1440 monitor): `omareel record --fullscreen` recorded `DisplayPort-3` through the Flatpak, `record --stop` finalised the file and left no recorder running, and `input.jsonl` held the pointer path sampled over X11. The editor opened the bundle and the export drew the synthetic cursor along that path.
- The launcher floats under i3 without a window rule (its fixed size), and follows the Omarchy theme's accent.

Not yet checked: a region or window pick through slop, clicks and keys (evdev) in a real recording, the countdown, the webcam bubble, two monitors, and desktop / microphone audio.

## Requirements

- Qt 6 Quick / Controls / Dialogs / Effects / Shapes / Layouts / Multimedia, `qt6-svg-plugins`, `qt6-qpa-plugins`, `ffmpeg`
- gpu-screen-recorder: the Flatpak Omaxian's recorder uses (`flatpak install flathub com.dec05eba.gpu_screen_recorder`), or one on `PATH`. The Flatpak cannot write to `/tmp`, so keep the output folder under your home (default `~/Videos/omareel`)
- `xrandr`, `setxkbmap`, `slop` (installed by `scripts/setup.sh`), `pactl` for audio
- Membership in the `input` group for clicks and keys (`sudo adduser $USER input`, then log in again)

Build: see `apt_build` in `omaxian.deps.json`, plus rustup (`install.sh` installs it).

## Install

```bash
community-apps/omareel/install.sh
```

CI builds omareel's pre-built binary (`.github/workflows/community-apps.yml`); until its pin PR
lands there is none, and `install.sh` builds with `bin/build`. When the local
Qt (`~/.local/opt/omaxian-qt6-<mm>`) has no ShaderTools, which apt cannot supply for Qt 6.10, it
builds against Qt 6.8 in a `debian:trixie` container (podman or docker) instead. That binary runs
on 6.8 and newer. When QtMultimedia exists only under `~/.local/lib/qt6/qml`, it installs a
wrapper that points at it, as Folio and Flowtunes do.

| Path | Role |
| ---- | ---- |
| `~/.local/bin/omareel` | app (a wrapper when QtMultimedia is under `~/.local`; the binary is then `~/.local/libexec/omareel`) |
| `~/.local/bin/omarecord` | upstream's legacy name |
| `~/.local/share/applications/omareel.desktop` | launcher |
| `~/.local/share/icons/hicolor/*/apps/omareel.*` | icons |

Bind the recording toggle in i3 (`~/.config/i3/config.d/`):

```
bindsym $mod+Mod1+r exec --no-startup-id ~/.local/bin/omareel record
```

## Smoke check

1. `omareel` opens the launcher, floating; the record button uses the theme's accent.
2. `omareel record`: drag a region (or click a window, or the desktop). A notification says the
   recording started. Move the pointer, click something.
3. `omareel record` again stops; the editor opens the bundle in `~/Videos/omareel/`.
4. The editor shows the synthetic cursor along your path and click rings; Export writes an MP4.
5. `pgrep -af 'gpu-screen-recorder -w'` prints nothing afterwards.

Debug log: start with `OMAREEL_DEBUG=1 omareel record …` and read `/tmp/omareel.log`.

## Uninstall

```bash
rm -f ~/.local/bin/omareel ~/.local/bin/omarecord ~/.local/libexec/omareel
rm -f ~/.local/share/applications/omareel.desktop
rm -f ~/.local/share/icons/hicolor/*/apps/omareel.{svg,png}
```

## License

MIT (upstream). Inter (SIL OFL 1.1) and Lucide icons (ISC): see `LICENSES/`.
