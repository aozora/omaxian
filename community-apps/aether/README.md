# Aether (Omaxian port)

Visual theming app: extract a 16-colour palette from a wallpaper (or pick a
preset / Base16 scheme), tune it, and apply it as an Omarchy theme. Full
upstream docs: [`README.upstream.md`](README.upstream.md) and [`docs/`](docs/).

Port of [omacom/aether](https://github.com/omacom/aether) **4.33.0**
(upstream commit `a7a7c37`, full SHA in `.omaxian-upstream-commit`; version in
`.omaxian-upstream-version`).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## How it themes Omaxian

**Apply** writes `~/.config/omarchy/themes/<name>/` (`colors.toml`,
`backgrounds/`, per-app files) and runs `omarchy-theme-set <name>`. Omaxian's
theme-set renders the bar, i3, dunst, terminals, GTK and icons from that
`colors.toml`, so the whole desktop follows. With a wallpaper, Aether first
runs `omarchy-theme-bg-set` and then theme-set with
`OMARCHY_THEME_SKIP_BACKGROUND=1`, so the wallpaper you picked stays.

Templates for Wayland-only apps (Hyprland, Waybar, mako, walker, hyprlock,
swayosd, wofi) are still generated; nothing on Omaxian reads them.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| AUR / `.deb` / `install.sh` from the AUR | Debian `install.sh` → `~/.local` (pinned CI binary, or `bin/build`) |
| `omarchy theme set` / `omarchy theme bg set` (group dispatcher) | `omarchy-theme-set` / `omarchy-theme-bg-set` (`internal/omarchy/cli.go`) |
| Omarchy detected by an `omarchy` command on `PATH` | Detected by `omarchy-theme-set` |
| `omarchy version` in the capability report | Not called (Omaxian has no such command); version left empty |
| Stock themes at `$OMARCHY_PATH/themes`, else `/usr/share/omarchy/themes` | Fallback is `~/.local/share/omarchy/themes` (Omaxian's per-user install) |
| Self-upgrade from GitHub releases when pacman does not own the binary | Built with `packageUpdateCommand` set: `aether upgrade` points at `scripts/install-community-apps.sh aether` and the update indicator is hidden (an upstream binary would drop the patches) |
| `wails build` | `bin/build`: `npm ci` + `vite build`, then `go build -tags desktop,production[,webkit2_41]` (bindings in `frontend/wailsjs` are committed upstream) |
| Go 1.25, Node ≥ 22.22 | Debian's Go 1.24 with `GOTOOLCHAIN=auto` (fetches 1.25 once); Debian's Node 20.19, which Vite accepts |
| Overlay window rules / monitor size via `hyprctl` | Unchanged; gated on `HYPRLAND_INSTANCE_SIGNATURE` (the overlay helper is unused) |
| Tests fake the `omarchy` dispatcher | Same fakes plus forwarding `omarchy-theme-*` shims (`internal/omaxiantest`) |
| Quickshell wallpaper / blueprint pickers (`contrib/quickshell`) | Not ported: Wayland layer-shell (`omarchy-plugin-check`: 6 patchable lines each) |
| `.github/`, `.husky/`, `.claude/`, `CLAUDE.md` | Dropped (Arch CI, upstream hooks and maintainer notes) |

## Requirements

Runtime (also in `omaxian.deps.json`): `libgtk-3-0t64`,
`libwebkit2gtk-4.1-0`, `gstreamer1.0-plugins-good`, `xdg-utils`.

Build: `golang-go`, `nodejs`, `npm`, `build-essential`, `pkg-config`,
`libgtk-3-dev`, `libwebkit2gtk-4.1-dev`. The first build downloads Go 1.25,
the npm packages and the Go modules.

## Install

```bash
community-apps/aether/install.sh
```

With a pinned binary in `.omaxian-prebuilt`, `install.sh` downloads it
(sha256-checked) and installs only the runtime packages. Otherwise, or with
`--from-source`, it builds with `bin/build`. See
[`../README.md`](../README.md#pre-built-binaries-omaxian-prebuilt).

| Path | Role |
| ---- | ---- |
| `~/.local/bin/aether` | app and headless CLI |
| `~/.local/share/applications/li.oever.aether.desktop` | launcher |
| `~/.local/share/applications/li.oever.aether.url-handler.desktop` | `aether://` link handler (set as default via `xdg-mime`) |
| `~/.local/share/icons/hicolor/512x512/apps/aether.png` | icon |

Aether keeps its own state in `~/.config/aether/` (blueprints, custom apps,
IPC socket).

## Tests

```bash
go test ./internal/... ./cli/...                 # as a normal user
go test -tags webkit2_41 .                       # needs frontend/dist (bin/build)
```

Two `internal/icontheme` tests expect an unreadable file and fail as root.

## Smoke check

1. `aether` opens; drop a wallpaper and **Extract**.
2. **Apply Theme**: the bar, i3 borders, terminals and wallpaper change, and
   `omarchy-theme-current` prints the theme name.
3. `aether --list-blueprints` and `aether --help` work without the GUI.
