# Community plugins (optional)

Omaxian-compatible **third-party** shell plugin ports live here. They are **not**
installed by `./deploy.sh` or `./install.sh`. Stock desktop code stays under
`omaxian/.local/share/omarchy/shell/plugins/`; this tree is opt-in only.

Runtime install target (always):

```text
~/.config/omarchy/plugins/<plugin-id>/
```

## Layout

One directory per plugin. Third-party contract: `manifest.json` at the **root**
of that directory (not nested under `panels/` / `bar/` like first-party).

```text
community-plugins/
  README.md
  <plugin-id>/
    manifest.json          # required: schemaVersion, id, name, version, kinds, entryPoints
    *.qml / helpers / …
```

### Rules

- Keep this folder **outside** `omaxian/` so deploy never copies it into `$HOME`.
- Do **not** add ports under `omaxian/.local/share/omarchy/shell/plugins/` or seed
  them in stock `shell.json`. First-party plugins are on by default; community
  ones must be added and enabled by the user.
- Prefer the upstream community plugin `id` when compatible. Use `omaxian.*` only
  for Omaxian-only forks that must not collide with reserved first-party ids.
- No symlinks inside a plugin tree — `omarchy-plugin-validate` rejects them.
- Before listing a port here, run:

  ```bash
  omarchy-plugin-check ./community-plugins/<plugin-id>
  omarchy-plugin-validate ./community-plugins/<plugin-id>
  ```

  Expect exit 0 from `omarchy-plugin-check`, or document known transforms in that
  plugin’s own notes.


## Catalog

| Directory                                       | Plugin id              | Upstream / notes                                                                                                                           | Status |
| ----------------------------------------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ------ |
| [`jankeesvw.nag`](jankeesvw.nag/)               | `jankeesvw.nag`        | [omarchy-nag](https://github.com/jankeesvw/omarchy-nag) — disposable alarms; calendar user timers → wall-clock sleeper, `paplay`/`pw-play` | Ported |
| [`jmaeder.swissweather`](jmaeder.swissweather/) | `jmaeder.swissweather` | [omarchy-swissweather](https://github.com/jmaeder/omarchy-swissweather) — MeteoSwiss bar weather; QML compatible as-is                     | Ported |

## Install (opt-in)

Plugins run unsandboxed inside `omarchy-shell`. Review the tree before enabling.

### From a git URL (preferred when published)

`omarchy-plugin-add` only accepts a git URL today (not a local path):

```bash
omarchy-plugin-check https://github.com/example/omarchy-foo.git
omarchy-plugin-add https://github.com/example/omarchy-foo.git --enable
```

### From this repo (local copy)

Until `omarchy-plugin-add` accepts a directory:

```bash
PLUGIN=community-plugins/<plugin-id>   # path from repo root
ID=$(jq -r .id "$PLUGIN/manifest.json")

omarchy-plugin-check "$PLUGIN"
omarchy-plugin-validate "$PLUGIN"

mkdir -p ~/.config/omarchy/plugins
rsync -a --delete -- "$PLUGIN/" "$HOME/.config/omarchy/plugins/$ID/"

omarchy-shell shell rescanPlugins
omarchy-plugin-enable "$ID"
```

Disable or remove later:

```bash
omarchy-plugin-disable "$ID"
omarchy-plugin-remove "$ID"
```

Settings → Plugins and Menu → Setup → Plugins also toggle enablement after the
plugin is installed under `~/.config/omarchy/plugins/`.

## Porting checklist

1. Clone or unpack the upstream community plugin.
2. Run `omarchy-plugin-check` — patch Wayland / Hyprland / PipeWire / systemd
   couplings (see `docs/omarchy-port/deltas.md` and `agents/skills/shell-dev.md`).
3. Place the result at `community-plugins/<plugin-id>/` with root `manifest.json`.
4. Re-run check + validate; add a catalog row above.
5. Do not wire it into stock `shell.json` or first-party `shell/plugins/`.
