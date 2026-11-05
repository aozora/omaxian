# disktree (Omaxian port)

GPUI treemap for finding what fills a disk, marking it, and removing it after
a review. Local directories and SSH hosts.

Port of [tobi/disktree](https://github.com/tobi/disktree) 0.11.0
(upstream commit `9b18b27`, pinned in `.omaxian-upstream-commit`). Full upstream
docs: [`README.upstream.md`](README.upstream.md).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| AUR `disktree-bin` / `yay -S` | Debian `install.sh` → `~/.local` via upstream `make install` |
| Arch rustc | **rustup** (`rust-toolchain.toml` → 1.97). Debian `rustc` 1.85 is too old |
| Hyprland `windowrule` float, class `disktree`, 1400×900 | i3 `for_window` snippet (`omaxian/i3-disktree.conf`), installed only when missing |
| Theme via `gpui-omarchy` | Unchanged. Reads `~/.local/state/omarchy/current/theme/colors.toml` |

GPUI already opens on X11 or Wayland. Pacman paths in the removal rules are
refusals (`/var/lib/pacman`, `/var/cache/pacman/pkg`), not a package manager
this port calls. The portable Linux build still embeds musl `disktree-scan`
helpers so an SSH scan can drop a static binary on the remote host.

## Requirements

Runtime (also in `omaxian.deps.json`):

- Vulkan (`libvulkan1`) and a GPU GPUI can drive
- X11 client libraries (`libx11-6`, `libxcb1`, `libxkbcommon-x11-0`)
- `libwayland-client0` (GPUI links it even for the X11 window)

Build: those `-dev` packages, plus rustup. `install.sh` installs toolchain 1.97
and the `x86_64-unknown-linux-musl` / `aarch64-unknown-linux-musl` targets.
No external C cross-compiler: the helpers link with rust-lld.

## Install

```bash
community-apps/disktree/install.sh
```

| Path | Role |
| ---- | ---- |
| `~/.local/bin/disktree` | app, with embedded scan helpers |
| `~/.local/share/applications/disktree.desktop` | launcher, including Open with for directories |
| `~/.local/share/icons/hicolor/scalable/apps/disktree.svg` | icon |
| `~/.config/i3/config.d/90_disktree.conf` | float rule, only if that file was missing |

Then `i3-msg reload` if the float rule was just added. Open **disktree** from
the launcher.

## Smoke check

1. Launch disktree and accept a scan of a small directory (not `/`).
2. The treemap should draw, and the side panel should show free space.
3. Switch theme (`omarchy-theme-set …`). Colours should follow.
4. On i3 the window should float at about 1400×900 when the snippet is installed.

## Uninstall

```bash
make -C community-apps/disktree uninstall PREFIX="$HOME/.local"
rm -f ~/.config/i3/config.d/90_disktree.conf
```

## License

MIT (upstream).
