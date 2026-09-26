# Speaker Calibrator (Omaxian PipeWire port)

Measure your speakers with a microphone and install a protected parametric
PipeWire filter-chain for the Omaxian bar.

Port of
[thefreshoffice/omarchy-speaker-calibrator](https://github.com/thefreshoffice/omarchy-speaker-calibrator)
(upstream commit `b142b02`).

Plugin id: `omaxian-speaker-pipewire-calibrator`. **PipeWire only** (needs
`pipewire` + `pipewire-pulse` + `wireplumber`). On PulseAudio, install
[`omaxian-speaker-pulseaudio-calibrator`](../omaxian-speaker-pulseaudio-calibrator/)
instead. Do not enable both.

Optional — not installed by `./deploy.sh`. See [`../README.md`](../README.md)
for the catalog install pattern.

## Omaxian deltas

| Upstream (Omarchy) | This port |
| ------------------ | --------- |
| Upstream user services for filter-chain + loudness + trial | Detached `pipewire -c …` + pidfiles under `$XDG_RUNTIME_DIR/omaxian-speaker-pipewire-calibrator/` |
| Arch `pkg add` / package names | `sudo apt install -y` (`python3-numpy`, `python3-scipy`, `lsp-plugins-lv2`) |
| Wayland clipboard helper | `xclip -selection clipboard` |
| Floating terminal launcher | `omarchy-launch-floating-terminal-with-presentation` |
| Plugin id `thefreshoffice.speaker-calibrator` | `omaxian-speaker-pipewire-calibrator` (module `omaxian.speaker-pipewire-calibrator`) |
| Sink `omarchy_speaker_tuning` | `omaxian_speaker_pipewire_tuning` (avoids clash with the PulseAudio plugin) |

Kept on purpose: native PipeWire live controls and the LV2 filter-chain graph.
This plugin is for PipeWire; `omarchy-plugin-check` may still flag those API
names as “route via pactl” — ignore that for this tree.

## Prerequisites

```bash
sudo apt install -y pipewire pipewire-pulse wireplumber \
  python3-numpy python3-scipy lsp-plugins-lv2 pulseaudio-utils xclip
```

Confirm the session is PipeWire:

```bash
pactl info | grep 'Server Name'
# expect: PulseAudio (on PipeWire …)
```

## Install

From the Omaxian repo root:

```bash
PLUGIN=community-plugins/omaxian-speaker-pipewire-calibrator
ID=$(jq -r .id "$PLUGIN/manifest.json")

omarchy-plugin-check "$PLUGIN"   # exit 1 from intentional pw-* is OK; see notes above
omarchy-plugin-validate "$PLUGIN"

mkdir -p ~/.config/omarchy/plugins
rsync -a --delete -- "$PLUGIN/" "$HOME/.config/omarchy/plugins/$ID/"

omarchy-shell shell rescanPlugins
omarchy-plugin-enable "$ID"
```

### Session re-arm

No systemd user units. If a calibration was left enabled, add to
`~/.xsessionrc` or an i3 `exec --no-startup-id` line:

```bash
/usr/bin/python3 -sB ~/.config/omarchy/plugins/omaxian-speaker-pipewire-calibrator/speaker-calibrate.py ensure-running
```

## Using it

1. Click the speaker icon in the bar.
2. Press **Calibrate speakers** (install measurement packages if prompted).
3. Stay quiet for about thirty seconds while six sweeps play.
4. A passing measurement installs itself; you hear the result through
   `omaxian_speaker_pipewire_tuning`.

Middle-click the bar icon to re-scan devices.

## Removing it

```bash
omarchy-plugin-remove omaxian-speaker-pipewire-calibrator
```

Press **Disable** in the panel first. Residuals:

| Path | What it is |
| ---- | ---------- |
| `~/.local/share/omaxian-speaker-pipewire-calibrator/` | profiles, checks, sweeps |
| `~/.config/pipewire/omaxian-speaker-pipewire-tuning.conf*` | filter-chain host config |
| `$XDG_RUNTIME_DIR/omaxian-speaker-pipewire-calibrator/` | pidfiles (gone after logout) |

```bash
/usr/bin/python3 -sB ~/.config/omarchy/plugins/omaxian-speaker-pipewire-calibrator/speaker-calibrate.py disable
rm -rf ~/.local/share/omaxian-speaker-pipewire-calibrator
rm -rf ~/.config/pipewire/omaxian-speaker-pipewire-tuning.conf \
       ~/.config/pipewire/omaxian-speaker-pipewire-tuning.conf.d
```

## Licence

MIT (same as upstream).
