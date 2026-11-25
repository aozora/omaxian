# Hype (Omaxian port)

Simple presentations written in Markdown, with a visual slide editor. Pick an
installed Omarchy theme and a font, add images, video and code, present, and
export to PDF or PowerPoint. Full upstream docs:
[`README.upstream.md`](README.upstream.md).

Port of [omacom/hype](https://github.com/omacom/hype) **0.7.1** plus one
translations update (upstream commit `8c347fc`, full SHA in
`.omaxian-upstream-commit`; version in `.omaxian-upstream-version`).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| `omarchy pkg add hype` (Arch package in omarchy-pkgs) | Debian `install.sh` → `~/.local` |
| Requires Qt ≥ 6.9 | Builds and runs on Qt 6.8 (Devuan Excalibur); the pre-built binary targets 6.8 |
| Version from the release tarball or `git describe` | From `.omaxian-upstream-version` (`git describe` here would give Omaxian's tags) |
| `VideoOutput.endOfStreamPolicy: KeepLastFrame` (Qt 6.9+) | Set through the item's id only where the property exists. On Qt 6.8 a finished video clears instead of holding its last frame |
| `VideoOutput.clearOutput()` (Qt 6.9+) when the slide's video changes | Called only where it exists. On 6.8 `stop()` already clears the picture. Unguarded, it threw and the next video never loaded |
| Inline SVG text in PDF exports | On Qt 6.8 it is drawn as outlines: it looks the same but can't be searched or selected (tests check the text on Qt ≥ 6.9 only) |
| Pictures in PDF exports (JPEG at 4K) | Qt 6.8's PDF writer subsamples JPEG colour (4:2:0). Photos look the same; one-pixel colour detail softens (tests check stripes on Qt ≥ 6.9 only) |
| Runtime dep `qt6-wayland` | Not installed. Uses XCB via `qt6-qpa-plugins` |
| Popup corners from the theme's `hyprland.conf` `rounding` | Unchanged: themes still ship the file, so popups follow it on i3 too |
| File dialogs via xdg-desktop-portal | Same, with `xdg-desktop-portal-gtk` |
| Theme and language from Omarchy paths | Unchanged — Omaxian writes the same files |

## Requirements

- Qt 6 Quick / Controls / Effects / Shapes / Multimedia, Qt SVG, Qt image formats
- `libwebp`, `ffmpeg` (animated exports), `source-highlight` (code colours)
- `xdg-desktop-portal` + GTK backend

Build: `cmake` + `qt6-base-dev` + `qt6-declarative-dev` + `qt6-multimedia-dev`
+ `qt6-svg-dev` + `libwebp-dev`. Stock Devuan Excalibur Qt 6.8 is enough.
Tests (`bin/test`) also need `qt6-pdf-dev`, `python3`, `fonts-noto-core` and
`fonts-jetbrains-mono`, and a UTF-8 locale.

## Install

```bash
community-apps/hype/install.sh
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
| `~/.local/bin/hype` | app and command-line tool |
| `~/.local/share/applications/hype.desktop` | launcher (`hype open %f`) |
| `~/.local/share/icons/hicolor/scalable/apps/hype.svg` | icon |

`hype` without arguments is a command-line tool (`hype help`); `hype open
[file]` opens the window. `hype skill install` adds its agent skill to
`~/.agents/skills` and `~/.claude/skills` (optional).

## Smoke check

1. Open Hype from the launcher; Ctrl+N starts a deck in the current theme.
2. Add a slide with an image and one with a video; Ctrl+O / Ctrl+S use the portal dialog.
3. Present; Space plays and pauses the video; moving to the next video slide plays it.
4. Export to PDF and PowerPoint; open both.
5. Switch the Omarchy theme; the window recolours.
