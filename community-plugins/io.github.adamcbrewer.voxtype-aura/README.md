# Voxtype Aura (Omaxian port)

A compact, theme-aware [Voxtype](https://github.com/peteonrails/voxtype)
dictation overlay for [Omaxian](https://github.com/aozora/omaxian) (Omarchy
on Devuan/Debian + X11/i3). Port of
[adamcbrewer/voxtype-aura](https://github.com/adamcbrewer/voxtype-aura)
(upstream commit `3bd8745`).

Plugin id: `io.github.adamcbrewer.voxtype-aura` (unchanged). Optional — not
installed by `./deploy.sh`. See [`../README.md`](../README.md) for the catalog
install pattern.

Aura appears at the top-center of the focused monitor while Voxtype is active:

- **LISTENING** with live microphone-level bars while recording.
- **TRANSCRIBING** with a sweeping animation while processing speech.
- **TRANSCRIBED** with a brief check mark after successful transcription.
- Hidden when Voxtype is idle.

![Voxtype Aura listening while speech is recorded](preview.png)

## Omaxian deltas

| Upstream (Omarchy) | This port |
| ----------------------------- | --------- |
| Compositor focused-monitor API | `Quickshell.I3` (T3) |
| Layer-shell `PanelWindow` + keyboard-focus / layer props | 1px host `PanelWindow` + `PopupWindow` `grabFocus: false` (T1; same picom-safe pattern as OSD) |
| Status / audio helpers expected on `PATH` | Plugin-local `bin/aura-status` and `bin/aura-audio` |
| User service unit to restart the daemon | `setsid -f voxtype daemon` / i3 autostart (no systemd) |
| Icon glyphs via `Style.font.family` | `JetBrainsMono Nerd Font` for mic/check glyphs |

## Requirements

| Package / binary | For |
| --- | --- |
| `voxtype` | Daemon + `voxtype status --follow` |
| `pulseaudio-utils` (`pacat`) | Listening bars when `/usr/bin/voxtype-audio-bridge` is absent |
| `python3` | Peak-meter fallback |
| `fonts-jetbrains-mono` (Nerd Font variant) | Overlay icons |
| `util-linux` (`setpriv`) | Preferred status-child reaping (optional) |

```bash
# Voxtype is often installed from upstream packages; ensure `voxtype` is on PATH.
sudo apt install pulseaudio-utils python3
```

Disable Voxtype's built-in OSD in `~/.config/voxtype/config.toml`:

```toml
[osd]
enabled = false
```

Start the daemon (Devuan/Debian — no user systemd unit):

```bash
setsid -f voxtype daemon
# or add to ~/.config/i3/config.d/ autostart
```

## Install

From the Omaxian repo root:

```bash
PLUGIN=community-plugins/io.github.adamcbrewer.voxtype-aura
ID=$(jq -r .id "$PLUGIN/manifest.json")

omarchy-plugin-check "$PLUGIN"
omarchy-plugin-validate "$PLUGIN"

mkdir -p ~/.config/omarchy/plugins
rsync -a --delete -- "$PLUGIN/" "$HOME/.config/omarchy/plugins/$ID/"

omarchy-shell shell rescanPlugins
omarchy-plugin-enable "$ID"
```

### Update

```bash
omarchy-plugin-update "$ID" --from "$PLUGIN"
```

### Remove

```bash
omarchy-plugin-remove "$ID"
```

To restore Voxtype's built-in display, set `[osd] enabled = true` and restart
the daemon.

## How it works

Aura is a keep-loaded service plugin. `bin/aura-status` streams
`voxtype status --follow --extended --format json`. `bin/aura-audio` prefers
`/usr/bin/voxtype-audio-bridge` when the Voxtype package ships it; otherwise it
runs a `pacat --record` peak meter (`bin/aura-audio-peak.py`). A valid transition from
`transcribing` to idle briefly shows the completion state. Unexpected status
data fails closed by hiding the overlay. If either helper exits, Aura retries
after one second.

## Credits

Upstream Voxtype Aura by Adam Brewer, inspired by Jon Henshaw's
[Voxtype Prism](https://github.com/jonhenshaw/voxtype-prism). See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Security

Plugins run unsandboxed inside `omarchy-shell`. Aura runs two fixed local
commands (plugin `bin/` helpers), accepts no user input, performs no network
requests, and reads no credentials. The `pacat` fallback opens the default
PulseAudio source while the plugin is enabled (same always-on shape as upstream
`voxtype-audio-bridge`).

## License

[MIT](LICENSE)
