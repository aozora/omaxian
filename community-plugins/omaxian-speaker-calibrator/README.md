# Speaker Calibrator (Omaxian port)

Measure your speakers with a microphone and install a protected parametric
calibration for the Omaxian bar.

Port of
[thefreshoffice/omarchy-speaker-calibrator](https://github.com/thefreshoffice/omarchy-speaker-calibrator)
(upstream commit `08be2c30c74ed9dfa845aab2d3d64185056502f3`).

Plugin id: `omaxian-speaker-calibrator`. Optional — not installed by
`./deploy.sh`. See [`../README.md`](../README.md) for the catalog install
pattern.

## Omaxian deltas

| Upstream (Omarchy) | This port |
| ------------------ | --------- |
| Dedicated filter-chain audio client + live port writes | PulseAudio null-sink + setsid `speaker-dsp.py` (SciPy biquads + `python3-lilv` LV2) |
| User service units for tuning + loudness | Pidfiles under `$XDG_RUNTIME_DIR/omaxian-speaker-calibrator/` + `setsid` |
| Distro package helper / source build for bankstown | `sudo apt install` (`python3-numpy`, `python3-scipy`, `python3-lilv`, `lsp-plugins-lv2`, `bankstown-lv2`) |
| Data under `~/.local/share/omarchy-speaker-calibrator/` | `~/.local/share/omaxian-speaker-calibrator/` |
| Virtual sink `omarchy_speaker_tuning` | `omaxian_speaker_tuning` |

Measurement, fitting, safety limits, and the panel UX follow upstream.

## Prerequisites

- PulseAudio (`pactl`, `parec`, `pacat`) — stock Omaxian audio
- For measuring: `python3-numpy`, `python3-scipy`
- For enabling a calibration: `python3-lilv`, `lsp-plugins-lv2`
- Optional Deep bass: `bankstown-lv2`

The panel can open a floating terminal to install missing packages via apt.

## Install

From the Omaxian repo root:

```bash
PLUGIN=community-plugins/omaxian-speaker-calibrator
ID=$(jq -r .id "$PLUGIN/manifest.json")

omarchy-plugin-check "$PLUGIN"
omarchy-plugin-validate "$PLUGIN"

mkdir -p ~/.config/omarchy/plugins
rsync -a --delete -- "$PLUGIN/" "$HOME/.config/omarchy/plugins/$ID/"

omarchy-shell shell rescanPlugins
omarchy-plugin-enable "$ID"
```

### Session re-arm

The DSP does not use systemd. If a calibration was left enabled, add to
`~/.xsessionrc` or an i3 `exec --no-startup-id` line:

```bash
/usr/bin/python3 -s ~/.config/omarchy/plugins/omaxian-speaker-calibrator/speaker-calibrate.py ensure-running
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
omarchy-plugin-remove omaxian-speaker-calibrator
```

Press **Disable** in the panel first so the DSP stops and the default sink is
restored. Removing the plugin deletes its directory only. Residuals:

| Path | What it is |
| ---- | ---------- |
| `~/.local/share/omaxian-speaker-calibrator/` | profiles, checks, sweeps |
| `$XDG_RUNTIME_DIR/omaxian-speaker-calibrator/` | dsp/loudness pidfiles + socket (gone after logout) |

After Disable, or if the plugin was removed while still active:

```bash
/usr/bin/python3 -s ~/.config/omarchy/plugins/omaxian-speaker-calibrator/speaker-calibrate.py disable
# or, if the plugin tree is already gone:
pkill -f speaker-dsp.py; pkill -f loudness-tracker.py
pactl list short modules | awk '/module-null-sink/ && /omaxian_speaker_tuning/{print $1}' | xargs -r -n1 pactl unload-module
rm -rf ~/.local/share/omaxian-speaker-calibrator
```

`bankstown-lv2` is a normal system package and is left installed.

## What leaves your machine

Nothing. No API, telemetry, or update check. Optional apt installs only run
when you press an install button. Microphone recordings stay under
`~/.local/share/omaxian-speaker-calibrator/`.

## Licence

MIT (same as upstream).
