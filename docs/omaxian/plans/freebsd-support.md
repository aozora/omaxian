# Omaxian on FreeBSD 15.x — implementation plan

## Context
Omaxian targets Debian/Devuan only. i3, picom, kitty, dunst, Qt 6 and **Quickshell** all exist on FreeBSD (`x11/quickshell` has been in ports since Jan 2026, version 0.3.2 for 15.x), so the desktop can run there too. Today nothing works on FreeBSD:
- The installer hard-exits on missing apt.
- About 128 `bin/` scripts use `#!/bin/bash`.
- The bar and commands read `/proc` and `/sys`, and call `nmcli`, `pactl`, `bluetoothctl`, `brightnessctl`, `busctl`, `loginctl` and `timedatectl`.
- Session env relies on Debian's `~/.xsessionrc`.

**Decisions taken:**
- **One tree with a platform layer.** No FreeBSD overlay tree.
- **Audio:** native OSS `mixer(8)`.
- **Wi-Fi:** `wpa_cli` + `ifconfig`.
- **Scope:** core desktop only, meaning installer, deploy, i3, the Quickshell bar and the core `omarchy-*` commands. Community plugins and apps come later.
- **Unsupported on FreeBSD in v1:** Bluetooth (no BlueZ), power profiles (no power-profiles-daemon), Wi-Fi band selection, gpu-screen-recorder and flatpak apps. These are **hidden**, not half-ported.

## Principles
- Prefer **portable rewrites** that work on both OSes, such as `pgrep -q`, `date -r`, `tail -r`-free logic and `sed` with a temp file. Branch with `case $OMARCHY_OS` only where the mechanism truly differs.
- One detection point: `OMARCHY_OS` = `linux|freebsd`, from `uname -s`.
  - Exported by `~/.xsessionrc` and the session script.
  - Recomputed by `platform.sh` when it is missing.
  - QML reads it with `Quickshell.env("OMARCHY_OS")`. `omarchy-launch-shell` makes sure it is set.
- **Keep `#!/bin/bash` and `/usr/bin/python3`.** This keeps upstream parity and the existing AGENTS.md style rule, so the port stays easy to sync. On FreeBSD, `setup.sh` creates the symlinks `/bin/bash → /usr/local/bin/bash` and `/usr/bin/python3 → /usr/local/bin/python3`. This also covers the roughly 20 hard-coded `"/usr/bin/python3"` uses in QML and the `^/bin/bash` regex in `scripts/i3_bar:184`.

## Phase 0 — Platform library (new)
Create `omaxian/.local/share/omarchy/lib/platform.sh`, sourced as `. "$OMARCHY_PATH/lib/platform.sh"`. It provides:
- `OMARCHY_OS`
- `plat_runtime_dir`, which replaces the `/run/user/$UID` fallbacks in `omarchy-shell`, `restart-shell`, `launch-shell`, `host` and `i3_bar`
- `plat_detach`: `setsid`, falling back to `daemon -f`
- `plat_lock`: `flock`, falling back to the `lockf` wrapper
- `plat_fuser_kill`: GNU `-k -TERM` vs BSD `-k -s TERM`
- `plat_mktemp_suffix`
- `plat_epoch_fmt`: `date -d @N` vs `date -r N`
- `plat_sed_inplace`: temp file plus `mv`
- `plat_acline`, `plat_battery_*` and `plat_lid`: `/sys` vs `sysctl hw.acpi.*`
- `plat_cpu_mem`: `/proc/stat` and `/proc/meminfo` vs `kern.cp_time`, `vm.stats.vm.*` and `hw.pagesize`
- `plat_default_route_if`: `ip route get` vs `route -n get default`
- `plat_if_bytes`: `/sys/class/net` vs `netstat -ibn`

Precedent to follow: the existing `OMARCHY_POWER_SUPPLY_PATH` override in `omarchy-battery-status`. `scripts/deploy.sh` must copy `lib/`. Check that it rsyncs the whole tree.

## Phase 1 — Install path
- **`scripts/lib/os.sh` and `scripts/lib/pkg.sh` (new):**
  - `os_id`
  - `pkg_update`, `pkg_available`, `pkg_installed`, `pkg_install`, `pkg_vercmp`
  - apt backend: today's logic. FreeBSD backend: `pkg rquery`, `pkg info -e`, `pkg install -y`, `pkg version -t`
- **`scripts/setup.sh`:**
  - Split the package arrays into Debian and FreeBSD sets. Mapping comes from the install audit:
    - `i3`, `qt6-declarative`, `quickshell`, `py311-i3ipc`, `jetbrains-mono`, `noto-emoji`, `ImageMagick7`, `newt` (whiptail), `inotify-tools` (verify), `setsid` and `flock` ports (if not in 15.x base, verify), `upower`, `xss-lock`, `i3lock`, `mate-polkit`, `xdg-user-dirs`, `bash`, `python3`
    - Dropped: NetworkManager, bluez, rfkill, brightnessctl, light, acpi, elogind, ppd, spice-vdagent
  - FreeBSD-only steps:
    - `sysrc dbus_enable=YES` and `service dbus start`
    - Prompt for the `kld_list` DRM module (`i915kms`/`amdgpu`)
    - `pw groupmod video -m $USER` and `pw groupmod operator -m $USER`
    - A devfs rule granting the `video` group access to `/dev/backlight/*`
    - The bash/python symlinks
    - `/etc/wpa_supplicant.conf`: make sure `ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel` and `update_config=1` are set, after backing it up
    - Root helpers installed with `install -d` + `install -g wheel`. Today's code uses `install -D -g root`, which is wrong on BSD.
    - Skip `Xsession.options` and the sysvinit ppd script.
  - Privileged power and sound actions follow the SKILL.md "Privilege Escalation" rules (model: `omarchy-dns`). Install a scoped sudoers rule in `/usr/local/etc/sudoers.d/omaxian` for `zzz`, `acpiconf -s 3`, `sysctl hw.snd.default_unit=*` and `service netif restart wlan*`.
- **`omaxian-install.sh`:**
  - `preflight` (around `:174-201`): detect the OS before the apt-tool loop and pick the tool list per OS.
  - `ensure_preflight_tools` (`:243-273`) and `confirm_deps` (`:535`): go through `pkg.sh`.
  - `distro_hint` / `quickshell_instructions_text` (`:864-937`): add `freebsd) pkg install quickshell`.
  - Fix `stat -c %s` (`:345,366`) and `date -Is` (`:94,99`).
  - The whiptail/dialog gauge protocol must work with newt's whiptail.
- **`bootstrap.sh`:** pkg branch for git, curl and whiptail.
- **`scripts/deploy.sh` (session):**
  - Keep `~/.xsessionrc` as the single env file. Add `OMARCHY_OS` and an `XDG_RUNTIME_DIR` fallback that creates `/tmp/runtime-$UID` with mode 0700 if it is unset.
  - On FreeBSD, seed `~/.xsession` and `~/.xinitrc` **only when missing**, warning otherwise. Both source `~/.xsessionrc` and `exec dbus-launch --exit-with-session i3`.
  - Keyboard seed: no `/etc/default/keyboard`, so read `XkbLayout` from `/usr/local/etc/X11/xorg.conf.d/*.conf`, falling back to `us`. Never overwrite an existing `keyboard.json`.

## Phase 2 — Commands (`omaxian/.local/share/omarchy/bin/`, `omaxian/.config/i3/`)

**Portable GNU-ism fixes** (no branching; safe on Linux too):
- `sed -i` in `theme-set`, `plugin-clone` and `locale-generate`
- `find -printf` in `theme-list` and `plugin-remove`
- `stat -c` in `dns`
- `date -d` in `weather-icon` and `reminder`
- `date +%s%3N` in `audio-output-volume`
- `base64 -w0` in `theme-set`
- `mktemp --suffix` in `i3lock-omaxian`, `capture-qr`, `capture-text` and `menu-share`
- `tac` in `powerprofiles-list`
- `install -D` in `dns`
- `pidof` in `i3_autostart:54`
- GNU dd flags in `keyboard-apply`
- `setsid`, `flock` and `fuser`: route through `platform.sh`

**FreeBSD backends:**

| Area | Files | FreeBSD mechanism |
|---|---|---|
| Power/session | `omarchy-host` | Add a `freebsd` backend: `shutdown -p now`, `shutdown -r now`, `sudo -n zzz`, `i3-msg exit`. No hibernate. |
| Battery/AC/lid | `battery-present`, `power-present`, `battery-status`, `monitor-list`, `i3_display_watch.sh` | `hw.acpi.battery.*`, `hw.acpi.acline`, `hw.acpi.lid_switch_state` via `platform.sh`. `upower` kept when present. |
| Backlight | `.config/i3/scripts/i3_brightness`, `config.d/02_keybindings.conf:68-73` | Keybinds call `i3_brightness` only. That script uses `backlight(8)` on FreeBSD and the existing tools on Linux. |
| Audio | `omarchy-audio-*`, `restart-audio`, `i3_volume`, `i3_audio`, `i3_mpd` | New `omarchy-audio-mixer` (hidden helper): `mixer -j`/`mixer` parsing, `/dev/sndstat` for the device list, `hw.snd.default_unit` (sudo) for the default device. It emits the same JSON shape the existing scripts and `Services/Audio.qml` consume. No per-app streams. `i3_audio` starts no daemon on FreeBSD. |
| Network | `network-status`, `network-speedtest`, `network-qr`, `network-password`, `restart-wifi`, `dns`, `shell/scripts/vpn.sh` | `ifconfig`, `route -n get`, `netstat -ibn`, `wpa_cli status/scan/scan_results/add_network/set_network/select_network/save_config`. New `omarchy-wifi` helper (scan/connect/forget, JSON). DNS via `resolvconf`. VPN via `ifconfig -g wg` / `-g tun`. `network-band` exits "unsupported". |
| Bluetooth, power profiles | `bluetooth-*`, `restart-bluetooth`, `powerprofiles-*` | Exit 2 with "unsupported on FreeBSD". Callers hide the feature. |
| Stats/info | `system-stats`, `system-info` (py), `agent-account-state` (`/proc/<pid>/stat`) | `sysctl`, `pkg query`, `ifconfig`, `df -k`, `ps -o lstart=`. |
| Time/locale/kbd | `timezone-set/-current/-list`, `menu-timezone`, `language`, `locale-generate`, `keyboard-apply`, `agent-usage-fireworks` | `tzsetup -s` plus `/var/db/zoneinfo`. Locales are prebuilt, so `locale-generate` is a no-op. `localectl` dropped and `setxkbmap` kept. |
| Notifications etc. | `notification-send:211`, `startup-launch:107`, `powerprofiles-set`, `Media.qml` | Replace `busctl` with `gdbus call` / `dbus-send`. This works on both OSes. `notification-send` is high-impact, so test it first. |
| Autostart | `i3_autostart` (VM detection via `/sys/class/dmi`, `systemd-detect-virt`), `i3_polkit` (agent paths) | `sysctl kern.vm_guest`, `kenv smbios.system.product`. Also probe `/usr/local/libexec` for the polkit agent. |
| Screen recording | `capture-screenrecording` | Hidden on FreeBSD in v1. |

## Phase 3 — Quickshell (`omaxian/.local/share/omarchy/shell/`)
- **Platform flag:** add `Commons/Platform.qml` singleton (`os`, `isFreeBSD`, and `has` flags for bluetooth, nm, ppd, battery and wifi). The flags are filled once from `OMARCHY_OS` plus a probe.
- **SysStats:** `plugins/bar/widgets/SysStats.qml` stops reading `/proc` directly and polls `omarchy-system-stats` (JSON), which goes through `platform.sh`. `scripts/gpu.sh` returns N/A on FreeBSD unless `nvidia-smi` is present.
- **Audio:** `Services/Audio.qml` gets a backend switch.
  - Linux: pactl, as today.
  - FreeBSD: `omarchy-audio-mixer`, polled every 1–2 s because there is no subscribe.
  - Keep the public API (`nodes`, `defaultAudioSink/Source`, `setVolume`, `toggleMute`) so the Microphone widget and the audio panel stay unchanged.
  - `Commons/UntypedInput.qml` imports `Quickshell.Services.Pipewire`. Check whether the FreeBSD port builds that module. If it doesn't, move the import behind a Loader.
- **Network:** `bar/widgets/Network.qml` and `panels/network/Panel.qml`/`Model.js` already check `Networking.backend === NetworkManager`. Add a `wpa` branch that drives `omarchy-network-status` and `omarchy-wifi`. Hide 802.1x editing and the nm-connection-editor entries on FreeBSD.
- **Battery / power panel:** keep UPower when `upowerd` reports a device. Otherwise fall back to polling `omarchy-battery-status`. Hide the power-profile row when ppd is unavailable.
- **Bluetooth panels and controlpanel `BluetoothTab`:** hidden when `!Platform.has.bluetooth`.
- **Plugin live-reload and input hotplug:**
  - `services/PluginRegistry.qml:727-760`: keep `inotifywait` if the inotify-tools port works (via libinotify). Replace `/proc/$p/cmdline` with `ps -o args= -p`.
  - `Commons/InputDevices.qml`: skip the `/run/udev` watch on FreeBSD and use polling.
- **Updates and menu:**
  - `scripts/updates.sh` and `updates-install.sh`: add a pkg branch (`pkg version -vRl'<'`, `pkg upgrade`).
  - `plugins/menu/MenuModel.js:455`: install guards go through a per-OS query.
  - `omarchy-menu.jsonc`: add an `os` filter key (or reuse the existing guard mechanism) to hide the Bluetooth, power profiles, Wi-Fi band and screen-recording entries.
- **Indicators:** `bar/indicators/ScreenRecording.qml`: change `pgrep --quiet` to `-q`.

## Phase 4 — Docs and agent guidance
- **README:** add a FreeBSD section covering install, the `startx`/display manager path and the unsupported features.
- **New `docs/omaxian/freebsd.md`:** the package map, rc.conf/devfs/sudoers changes made by setup, and the list of features that differ.
- **`AGENTS.md`:** describe Omaxian as Debian/Devuan **and FreeBSD 15**. Add rules:
  - Use `lib/platform.sh`.
  - Avoid GNU-only flags.
  - Use `OMARCHY_OS`.
- **Skill files:** update `agents/skills/install-scripts.md` and `shell-dev.md`, and the end-user `default/agents/skills/omaxian/SKILL.md`.
- **Later:** FreeBSD hints for `plugin-check`, together with the community plugins and apps work. Note that `prebuilt.sh` already falls back to source builds because `uname -m` returns `amd64`.

## Commit sequencing (atomic)
1. `platform.sh` plus the portable GNU-ism fixes. Linux behaviour must not change.
2. `pkg.sh`/`os.sh` and the installer, setup and deploy FreeBSD branches.
3. Each command area as its own commit: host, battery, backlight, audio, network, stats, time/locale, notifications.
4. QML: Platform singleton, SysStats, Audio, Network, Battery, then the hiding of unsupported features.
5. Docs.

## Verification
- **Linux regression (every commit):**
  - `bash -n` and `shellcheck` on the touched scripts.
  - `./scripts/deploy.sh`, then log out and back in (never `omarchy-restart-shell` from an agent).
  - `omarchy-shell shell ping` (expect `ok`) and `omarchy-shell shell listPlugins`.
  - Visual checks of the bar, audio, network and battery per `agents/skills/visual-verification.md`.
- **Portability lint:** add a grep check for `sed -i[^ ']`, `-printf`, `stat -c`, `date -d`, `base64 -w`, `--suffix`, `/proc/`, `/sys/` outside `platform.sh` and the Linux branches. Run it as part of review.
- **FreeBSD 15.0 VM** (bhyve or QEMU, with Xorg and a virtio/scfb GPU):
  - Run `./omaxian-install.sh` end to end, then `startx`.
  - `omarchy-shell shell ping`.
  - Bar renders. CPU and RAM stats are sane against `top`.
  - Volume keys change `mixer` output.
  - `omarchy-host logout`/`reboot` work.
  - The theme switch works.
  - Bluetooth and power profiles are hidden.
- **Real FreeBSD laptop** (needed for what a VM can't show): battery percentage and AC state, the `backlight` keys, Wi-Fi scan/connect through the panel, lid state, and `zzz` suspend.
