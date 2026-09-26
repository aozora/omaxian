# Speaker Calibrator (Omaxian PulseAudio port)

Measure your speakers with a microphone and install a protected parametric
calibration for the Omaxian bar.

Port of
[thefreshoffice/omarchy-speaker-calibrator](https://github.com/thefreshoffice/omarchy-speaker-calibrator)
(upstream commit `08be2c30c74ed9dfa845aab2d3d64185056502f3`).

Plugin id: `omaxian-speaker-pulseaudio-calibrator`. Optional — not installed by
`./deploy.sh`. See [`../README.md`](../README.md) for the catalog install
pattern.

## Omaxian deltas

| Upstream (Omarchy) | This port |
| ------------------ | --------- |
| Dedicated filter-chain audio client + live port writes | PulseAudio null-sink + setsid `speaker-dsp.py` (RBJ biquads + soft ceiling) |
| User service units for tuning + loudness | Pidfiles under `$XDG_RUNTIME_DIR/omaxian-speaker-pulseaudio-calibrator/` + `setsid` |
| Distro package helper / source build for bankstown | `sudo apt install` (see Prerequisites); bankstown UI present but not hosted yet |
| Data under `~/.local/share/omarchy-speaker-calibrator/` | `~/.local/share/omaxian-speaker-pulseaudio-calibrator/` |
| Virtual sink `omarchy_speaker_tuning` | `omaxian_speaker_tuning` |

Helpers run with `python3 -sB` so they never write `__pycache__` under the
plugin tree. The shell file-watches that directory; bytecode writes used to
hot-reload the panel and abort calibration mid-sweep.

On Framework/AMD UCM machines the panel prefers the Digital Microphone over
the often-silent Stereo (headset jack) mic, and switches the card from
Headphones to Speakers when measuring so the laptop mics can hear the sweeps.

Measurement, fitting, safety limits, and the panel UX follow upstream.

## Prerequisites

```bash
sudo apt install -y python3-numpy python3-scipy pulseaudio-utils
```

| Package | Needed for |
| ------- | ---------- |
| `python3-numpy` | Measuring, fitting, and the userspace DSP |
| `python3-scipy` | Measuring and fitting |
| `pulseaudio-utils` | `pactl`, `parec`, `pacat` (also provided by `pipewire-pulse` on some setups) |

No `python3-lilv` or `lsp-plugins-lv2` — the DSP uses pure-Python biquads and a soft ceiling. Deep bass (`bankstown-lv2`) remains optional in the UI but is not hosted yet.

The panel can open a floating terminal to install missing measurement packages if they are absent.

## Install

From the Omaxian repo root:

```bash
PLUGIN=community-plugins/omaxian-speaker-pulseaudio-calibrator
ID=$(jq -r .id "$PLUGIN/manifest.json")

omarchy-plugin-check "$PLUGIN"
omarchy-plugin-validate "$PLUGIN"

mkdir -p ~/.config/omarchy/plugins
rsync -a --delete -- "$PLUGIN/" "$HOME/.config/omarchy/plugins/$ID/"

omarchy-shell shell rescanPlugins
omarchy-plugin-enable "$ID"
```

If you previously installed `omaxian-speaker-calibrator`, remove that id first and
move profiles if you want to keep them:

```bash
omarchy-plugin-remove omaxian-speaker-calibrator
mv ~/.local/share/omaxian-speaker-calibrator ~/.local/share/omaxian-speaker-pulseaudio-calibrator
```

### Session re-arm

The DSP does not use systemd. If a calibration was left enabled, add to
`~/.xsessionrc` or an i3 `exec --no-startup-id` line:

```bash
/usr/bin/python3 -sB ~/.config/omarchy/plugins/omaxian-speaker-pulseaudio-calibrator/speaker-calibrate.py ensure-running
```

## Using it

1. Click the speaker icon in the bar.
2. Press **Calibrate speakers** (install measurement packages if prompted).
3. Stay quiet for about thirty seconds while six sweeps play.
4. A passing measurement installs itself; you hear the result through
   `omaxian_speaker_tuning`.

Middle-click the bar icon to re-scan devices. Failed measurements are kept for
diagnosis but never installed.

## Removing it

```bash
omarchy-plugin-remove omaxian-speaker-pulseaudio-calibrator
```

Press **Disable** in the panel first so the DSP stops and the default sink is
restored. Removing the plugin deletes its directory only. Residuals:

| Path | What it is |
| ---- | ---------- |
| `~/.local/share/omaxian-speaker-pulseaudio-calibrator/` | profiles, checks, sweeps |
| `$XDG_RUNTIME_DIR/omaxian-speaker-pulseaudio-calibrator/` | dsp/loudness pidfiles + socket (gone after logout) |

After Disable, or if the plugin was removed while still active:

```bash
/usr/bin/python3 -sB ~/.config/omarchy/plugins/omaxian-speaker-pulseaudio-calibrator/speaker-calibrate.py disable
# or, if the plugin tree is already gone:
pkill -f speaker-dsp.py; pkill -f loudness-tracker.py
pactl list short modules | awk '/module-null-sink/ && /omaxian_speaker_tuning/{print $1}' | xargs -r -n1 pactl unload-module
rm -rf ~/.local/share/omaxian-speaker-pulseaudio-calibrator
```

`bankstown-lv2` is a normal system package and is left installed.

## What leaves your machine

Nothing. No API, telemetry, or update check. Optional apt installs only run
when you press an install button. Microphone recordings stay under
`~/.local/share/omaxian-speaker-pulseaudio-calibrator/`.

## Licence

MIT (same as upstream).
