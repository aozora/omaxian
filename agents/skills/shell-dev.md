# Omaxian Shell Development

Read this before editing the Quickshell desktop under
`omaxian/.local/share/omarchy/shell/`.

The Quickshell desktop runs as a single long-running process out of
`$OMARCHY_PATH/shell`. i3 autostart launches it with
`omarchy-launch-shell` (`quickshell -n -p "$OMARCHY_PATH/shell"`). Do not
start additional standalone Quickshell instances for individual components.

Run `omarchy-restart-shell` after making changes to QML files **only when
you mean to** — it stops picom, kills Quickshell, relaunches, then starts
picom. Prefer **log out / log in** after `./deploy.sh`. Never chain
restart-shell with `i3-msg reload`. `shell.json` and
`~/.config/omarchy/shell.toml` are file-watched and usually apply live
(unless a deploy lock is held).

**Agent hard rule:** never run `omarchy-restart-shell`, never `pkill` /
`kill` Quickshell or picom, and never stop picom for verification. Concurrent
restarts and glx + ARGB teardown have taken down the whole X session. Apply
QML by editing the repo, then tell the user to `./deploy.sh` and **log out /
log in**. Do not hot-reload plugins on a live session (rebuilds the bar under
picom and freezes X).

## Paths

| Repo | Deployed |
|------|----------|
| `omaxian/.local/share/omarchy/shell/` | `$OMARCHY_PATH/shell/` (`~/.local/share/omarchy/shell/`) |
| `omaxian/.local/share/omarchy/shell.json` | `$OMARCHY_PATH/shell.json` (stock defaults) |
| — | `~/.config/omarchy/shell.json` (user; seeded once by `deploy.sh`) |

Edit QML under the repo `shell/` tree, then `./deploy.sh`. Do not treat
`omarchy-quattro/shell/` as the working tree. Change stock bar defaults in
`omaxian/.local/share/omarchy/shell.json`; live Settings / layout edits go
only to `~/.config/omarchy/shell.json` and are not overwritten by redeploy.

## Plugin contract

- First-party plugins live directly under `shell/plugins/` or one category
  level deeper, such as `shell/plugins/panels/weather/`. First-party bar-only
  widgets may use adjacent `*.manifest.json` files. Third-party plugins live
  at `~/.config/omarchy/plugins/<id>/` with a `manifest.json` at the root.
- Optional community ports for this project live in repo-root
  `community-plugins/<id>/` (outside `omaxian/`, not deployed). Port them as
  third-party trees; never merge them into `shell/plugins/` or stock
  `shell.json`. See [`community-plugins/README.md`](../../community-plugins/README.md).
- Every plugin manifest declares `schemaVersion`, `id`, `name`, `version`,
  `kinds`, and `entryPoints`. See `shell/services/PluginRegistry.qml` for the
  current contract; fields such as `activation` are optional.
- First-party ids use `omarchy.*` when the plugin is a port of upstream, and
  `omaxian.*` when it has no upstream counterpart (dock, settings, control
  panel, sysstats, vpn, apt updates, help, …).
- Entry-point QML files are `Item`s (not `ShellRoot`), and accept the
  shell-injected properties `omarchyPath`, `shell`, `manifest`, and
  `pluginRegistry` / `barWidgetRegistry` as appropriate.
- Panel / overlay / menu plugins must expose `open(payloadJson)` and
  `close()` lifecycle methods for `shell summon` and `shell hide`.
- Do not re-introduce `WlrLayershell`, `Quickshell.Hyprland`,
  `Quickshell.Services.Pipewire`, or systemd. X11 popups use `PopupWindow` /
  `Ui/KeyboardPanel` / `Ui/CenteredModal` / `Ui/PopupCard`. See
  [`docs/omarchy-port/deltas.md`](../../docs/omarchy-port/deltas.md).
- Before adding a community plugin, run `omarchy-plugin-check` on it.

## IPC

- `omarchy-shell` is the canonical IPC entry point. It forwards to the
  running shell and does not start it. Prefer it over re-implementing direct
  Quickshell socket calls in every CLI.
- The `shell` IPC target exposes lifecycle and configuration methods including
  `ping`, `summon`, `hide`, `toggle`, `call`, `rescanPlugins`, `reloadConfig`,
  `setPluginEnabled`, and `listPlugins`.
- Individual plugins register their own IPC targets, named for the plugin
  rather than for where they appear. There is no `bar` target.

Smoke after a shell change:

```bash
omarchy-shell shell ping
omarchy-shell shell listPlugins | jq length
```

## Editing widget files with glyphs

Widget files in `shell/plugins/bar/widgets/` contain Nerd Font glyphs as raw
unicode characters. Agent file-editing tools can strip multi-byte codepoints
in some positions — do **not** rewrite widget files wholesale through those
tools. For glyph fixes, make a targeted edit with the surrounding context, or
use a Python script that inserts codepoints via `chr(0xXXXXX)`.
