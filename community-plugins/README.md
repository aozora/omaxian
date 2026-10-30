# Community plugins (optional)

Omaxian-compatible **third-party** shell plugin ports live here. They are **not**
installed by the desktop `setup` / `install` / `deploy` scripts. Stock desktop
code stays under `omaxian/.local/share/omarchy/shell/plugins/`; this tree is
opt-in only.

| Script | Installs community plugins? |
| --- | --- |
| `scripts/setup.sh` (packages / system) | No |
| `scripts/install.sh` (themes / `bin/`) | No |
| `scripts/deploy.sh` (`omaxian/` → `$HOME`) | No |
| `omaxian-install.sh` (TUI, optional step) | Yes, if you accept and select ports |
| `scripts/install-community-plugins.sh` | Yes (selected ports + apt deps) |

Desktop install is documented in
[`docs/omaxian/install-scripts.md`](../docs/omaxian/install-scripts.md). First-time
users can pick plugins from the TUI after the desktop phases. Use **this**
README for manual installs and for updating ports under
`~/.config/omarchy/plugins/`.

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
    omaxian.deps.json      # optional: Debian apt + manual follow-ups for the TUI/helper
    *.qml / helpers / …
```

### `omaxian.deps.json` (Debian deps)

Omarchy’s `manifest.json` schema has no package list. Omaxian-only packaging
metadata goes here so the installer can `apt-get install` what a selected port
needs:

```json
{
  "apt": ["qml6-module-qtmultimedia", "v4l-utils"],
  "manual": [
    "Install Proton pass-cli from https://protonpass.github.io/pass-cli/ (not in Debian apt)"
  ]
}
```

- `apt` — package names only (no URLs, no `curl | bash`).
- `manual` — human follow-ups shown after install (non-apt tools, backends).
- Missing file ⇒ no apt packages for that port (still installable).

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

| Directory                                                       | Plugin id                      | Upstream / notes                                                                                                                           | Status |
| --------------------------------------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------ | ------ |
| [`jankeesvw.nag`](jankeesvw.nag/)                               | `jankeesvw.nag`                | [omarchy-nag](https://github.com/jankeesvw/omarchy-nag) — disposable alarms; calendar user timers → wall-clock sleeper, `paplay`/`pw-play` | Ported |
| [`io.github.guiestrela.weather`](io.github.guiestrela.weather/) | `io.github.guiestrela.weather` | [guiestrela/weather](https://github.com/guiestrela/weather) — Better Weather (Open-Meteo / wttr.in / RainViewer); helper accepts Debian `775` ancestors under `$HOME` | Ported |
| [`io.github.kaiizu.runcat`](io.github.kaiizu.runcat/)           | `io.github.kaiizu.runcat`      | [kaiizu/runningcat](https://github.com/kaiizu/runningcat) — RunCat-style CPU cat; click → sysmon, settings via `setBarWidget` | Ported |
| [`harshith.system-monitor`](harshith.system-monitor/)           | `harshith.system-monitor`      | [omarchy-system-monitor](https://github.com/Harshith292002/omarchy-system-monitor) — `/proc`/`/sys` dashboard; btop via `sysmon.sh` | Ported |
| [`josh2c.protonpass`](josh2c.protonpass/)                       | `josh2c.protonpass`            | [omarchy-protonpass](https://github.com/josh2c/omarchy-protonpass) — Proton Pass search/copy via `pass-cli`; `xclip`/`xsel`, floating terminal | Ported |
| [`omaxian-speaker-pulseaudio-calibrator`](omaxian-speaker-pulseaudio-calibrator/) | `omaxian-speaker-pulseaudio-calibrator` | [omarchy-speaker-calibrator](https://github.com/thefreshoffice/omarchy-speaker-calibrator) — PulseAudio-only port (userspace DSP + null sink) | Ported |
| [`omaxian-speaker-pipewire-calibrator`](omaxian-speaker-pipewire-calibrator/) | `omaxian-speaker-pipewire-calibrator` | Same upstream — PipeWire-only port (filter-chain + `pw-cli`; systemd → setsid) | Ported |
| [`omamail`](omamail/)                                           | `omamail`                      | [huacnlee/omamail](https://github.com/huacnlee/omamail) — Gmail/HEY/JMAP/IMAP + Rust backend; Wayland clipboard → Qt clipboard / `xclip` | Ported |
| [`io.github.adamcbrewer.voxtype-aura`](io.github.adamcbrewer.voxtype-aura/) | `io.github.adamcbrewer.voxtype-aura` | [voxtype-aura](https://github.com/adamcbrewer/voxtype-aura) — Voxtype dictation overlay; T1 PopupWindow + T3 I3; plugin-local status/audio helpers | Ported |
| [`io.github.canclini.calculator`](io.github.canclini.calculator/) | `io.github.canclini.calculator` | [omarchy-calculator](https://github.com/canclini/omarchy-calculator) — quick calculator overlay; T1 CenteredModal, `xclip`/`xsel` | Ported |
| [`com.omastorm.radar`](com.omastorm.radar/) | `com.omastorm.radar` | [omastorm](https://github.com/wesleygrimes/omastorm) — live NEXRAD/OPERA radar; `omarchy-shell` / `omarchy-restart-shell`, no Hyprland | Ported |
| [`io.github.kristoferlund.webcam`](io.github.kristoferlund.webcam/) | `io.github.kristoferlund.webcam` | [omarchy-webcam](https://github.com/kristoferlund/omarchy-webcam) — V4L2 preview + controls; Debian `qml6-module-qtmultimedia` / `v4l-utils` | Ported |
| [`alexzeitler.ytdlp`](alexzeitler.ytdlp/) | `alexzeitler.ytdlp` | [omarchy-yt-dlp-plugin](https://github.com/AlexZeitler/omarchy-yt-dlp-plugin) — yt-dlp download queue; `xclip`/`xsel`, floating terminal for checkout sync | Ported |
| [`mirecad.omakeepick`](mirecad.omakeepick/) | `mirecad.omakeepick` | [omakeepick](https://github.com/mirecad/omakeepick) — KeePass picker + Rust daemon; `xclip`/`xdotool`, PopupWindow overlay (no layer-shell) | Ported |

## Install (opt-in)

Prerequisite: a working Omaxian desktop (see
[`docs/omaxian/install-scripts.md`](../docs/omaxian/install-scripts.md)).
`omarchy-plugin-check`, `omarchy-plugin-add`, and friends live on `PATH` only
after `scripts/install.sh` (and a login that inherits `$OMARCHY_PATH/bin`).

Plugins run unsandboxed inside `omarchy-shell`. Review the tree before enabling.

### Via the TUI / helper (from this repo)

During `./omaxian-install.sh`, accept the community-plugins step and pick ports.
Or from an existing desktop:

```bash
./scripts/install-community-plugins.sh --list
./scripts/install-community-plugins.sh <dir-or-id>…
# installs omaxian.deps.json apt packages, rsyncs, best-effort enable
```

### From a git URL (preferred when published upstream)

`omarchy-plugin-add` only accepts a git URL today (not a local path):

```bash
omarchy-plugin-check https://github.com/example/omarchy-foo.git
omarchy-plugin-add https://github.com/example/omarchy-foo.git --enable
```

### From this repo (manual rsync)

Until `omarchy-plugin-add` accepts a directory. Prefer
`scripts/install-community-plugins.sh` above. Manual recipe from the **repo
root** (empty `PLUGIN` would make `rsync` copy `/` — keep the checks):

```bash
# Subshell so set -e / exit cannot close an interactive terminal.
(
  set -euo pipefail
  PLUGIN=community-plugins/<plugin-id>   # path from repo root
  [[ -f $PLUGIN/manifest.json ]] || { echo "missing $PLUGIN/manifest.json (cwd=$(pwd))" >&2; exit 1; }
  ID=$(jq -r .id "$PLUGIN/manifest.json")
  [[ -n $ID && $ID != null ]] || { echo "bad plugin id" >&2; exit 1; }

  omarchy-plugin-check "$PLUGIN"
  omarchy-plugin-validate "$PLUGIN"

  mkdir -p ~/.config/omarchy/plugins
  rsync -a --delete -- "$PLUGIN/" "$HOME/.config/omarchy/plugins/$ID/"

  # Needs a live omarchy-shell (omarchy-shell shell ping → ok).
  omarchy-shell shell rescanPlugins
  # rescan is async; omarchy-plugin-enable waits briefly for the id to appear
  omarchy-plugin-enable "$ID"
)
```

### Update

Community ports change over time (upstream syncs, X11 fixes). Re-apply without
removing enablement or mailbox/config state:

**Git install** (cloned with `omarchy-plugin-add`):

```bash
omarchy-plugin-update                 # every git-managed plugin
  "$ID"           # one id
```

**Local install** (rsync from this tree):

```bash
omarchy-plugin-check "$PLUGIN"
omarchy-plugin-validate "$PLUGIN"
omarchy-plugin-update "$ID" --from "$PLUGIN"
```

`--from` validates the source, replaces `~/.config/omarchy/plugins/$ID/`, and
rolls back if the new tree fails validation. Then `rescanPlugins` runs
automatically. Menu → Setup → Plugins → Update Plugins covers the git path.

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
4. Add `omaxian.deps.json` when the plugin needs Debian packages or has non-apt
   prerequisites (`apt` + `manual` arrays).
5. Re-run check + validate; add a catalog row above.
6. Do not wire it into stock `shell.json` or first-party `shell/plugins/`.
7. Do not add the port to `scripts/setup.sh` / `install.sh` / `deploy.sh` — keep
   it outside `omaxian/` so deploy never copies it into `$HOME`.

## See also

- [`docs/omaxian/install-scripts.md`](../docs/omaxian/install-scripts.md) — TUI,
  `scripts/setup.sh` / `install.sh` / `deploy.sh`, community helper
- [`docs/omaxian/plugin-check.md`](../docs/omaxian/plugin-check.md) —
  `omarchy-plugin-check` reference
