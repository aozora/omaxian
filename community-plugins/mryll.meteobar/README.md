# Meteobar (Omaxian port)

Open-Meteo weather in the Omaxian bar. Catalog copy of
[mryll/meteobar](https://github.com/mryll/meteobar) (upstream commit `dd18463`,
plugin version 0.5.3).

Plugin id: `mryll.meteobar` (unchanged). Optional — not installed by
`./deploy.sh`. See [`../README.md`](../README.md).

The bar shows a condition glyph and temperature. Click opens a panel with
current conditions, the next 12 hours, and the next 6 days. Middle-click
refreshes. The panel footer has a refresh control next to the last-update time.

## Omaxian deltas

| Upstream (Omarchy / Arch) | This port |
| ------------------------- | --------- |
| AUR `meteobar-bin` install hint | `make -C ~/.config/omarchy/plugins/mryll.meteobar install PREFIX=~/.local` |
| Wayland clipboard for the copy-install button | `xclip` / `xsel` (same pattern as first-party network panel) |
| Distro package for the CLI | Bundled Rust sources; build with `cargo` / `make install` |
| Marketplace / Hyprland docs | i3 install steps below |

`omarchy/BarWidget.qml` and `omarchy/Panel.qml` already use `KeyboardPanel`
(X11-capable in Omaxian). No Hyprland / layer-shell / PipeWire / systemd
couplings in the QML.

## Dependencies

- **`meteobar` on `PATH`** — build from this tree (needs `cargo`, `rustc`, and
  a C toolchain / OpenSSL headers for `reqwest`):

  ```bash
  # Debian / Devuan example
  sudo apt install cargo rustc build-essential pkg-config libssl-dev
  ```

- Nerd Font glyphs (Omaxian bar font)
- `xclip` or `xsel` (copy install command when the CLI is missing)
- A running `omarchy-shell`

Optional: `fonts-font-awesome` 7+ if you set `iconSet` to `fontawesome`.

## Install

From the Omaxian repo root:

```bash
PLUGIN=community-plugins/mryll.meteobar
ID=$(jq -r .id "$PLUGIN/manifest.json")

omarchy-plugin-check "$PLUGIN"
omarchy-plugin-validate "$PLUGIN"

mkdir -p ~/.config/omarchy/plugins
rsync -a --delete -- "$PLUGIN/" "$HOME/.config/omarchy/plugins/$ID/"

# Build and install the CLI (once; ~/.local/bin must be on PATH)
make -C "$HOME/.config/omarchy/plugins/$ID" install PREFIX=~/.local
hash -r
command -v meteobar   # expect: ~/.local/bin/meteobar

omarchy-shell shell rescanPlugins
omarchy-plugin-enable "$ID"   # default section: right
```

### Replacing the built-in weather widget

Omaxian ships `omarchy.weather`. The two can run side by side; one is usually
enough. Remove `omarchy.weather` from the bar layout in Settings → Bar, or from
`bar.layout` in `~/.config/omarchy/shell.json`.

i3 keybind examples:

```
bindsym $mod+Ctrl+w exec --no-startup-id omarchy-shell mryll.meteobar toggle
bindsym $mod+Ctrl+Shift+w exec --no-startup-id omarchy-shell mryll.meteobar refresh
```

## Settings

In `~/.config/omarchy/shell.json`, on the plugin’s entry (or Settings → Plugins):

| Key | Default | Meaning |
| --- | --- | --- |
| `refreshMinutes` | `15` | Poll interval (1–180) |
| `units` | `metric` | `metric` or `imperial` |
| `location` | `""` | City / `City, CC`; empty = IP geolocation |
| `iconSet` | `nerd` | `nerd`, `weather`, `emoji`, `fontawesome` |
| `colorMode` | `full` | `full`, `none`, `bar-only`, `panel-only` |
| `language` | `""` | `en` / `de`; empty follows locale (shell.json only) |

## Controls

| Action | Result |
| --- | --- |
| Left click | Open / close the forecast panel |
| Middle click | Refresh now |
| Panel footer refresh | Same forced refresh while the panel stays open |

## Data

Forecasts come from [Open-Meteo](https://open-meteo.com/) (no API key). Location
resolution uses Open-Meteo geocoding or IP lookup via ipwho.is when `location`
is empty. Theme colors prefer
`~/.local/state/omarchy/current/theme/colors.toml`.

## Remove

```bash
omarchy-plugin-remove mryll.meteobar
rm -f ~/.local/bin/meteobar   # optional
```

## Licence

MIT — see [LICENSE](LICENSE). Upstream copyright mryll.
