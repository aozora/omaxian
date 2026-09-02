#!/bin/bash
# setup.sh — install every system dependency Omaxian needs on a fresh
# Debian (systemd or sysvinit) or Devuan install. Idempotent; safe to re-run.
#
#   sudo ./setup.sh              required + recommended + the tools the scripts call
#   sudo ./setup.sh --minimal    only the hard-required set (no media/menus/extras)
#   sudo ./setup.sh --optional   also VM / GPU / niche extras (spice, radeontop, …)
#   sudo ./setup.sh --deploy     after installing, run ./install.sh && ./deploy.sh as you
#
# Step 1 always clones upstream Omarchy into omarchy-quattro/ (pinned; override
# with OMARCHY_UPSTREAM_URL / OMARCHY_UPSTREAM_REF). It does NOT deploy the port
# itself (install.sh + deploy.sh) beyond the bundled fonts and the one
# session-D-Bus toggle Quickshell needs to reach the bus.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Upstream Omarchy is cloned into omarchy-quattro/ (pinned), not vendored.
# Override with: OMARCHY_UPSTREAM_URL=… OMARCHY_UPSTREAM_REF=…
UPSTREAM_URL="${OMARCHY_UPSTREAM_URL:-https://github.com/omacom/omarchy.git}"
UPSTREAM_REF="${OMARCHY_UPSTREAM_REF:-v4.0.2}"

WITH_RECOMMENDED=1
WITH_OPTIONAL=0
RUN_DEPLOY=0
for arg in "$@"; do
	case "$arg" in
		--minimal)   WITH_RECOMMENDED=0 ;;
		--optional)  WITH_OPTIONAL=1 ;;
		--deploy)    RUN_DEPLOY=1 ;;
		-h|--help)   sed -n '2,14p' "$0"; exit 0 ;;
		*)           echo "unknown option: $arg" >&2; exit 2 ;;
	esac
done

# --- step 1: populate omarchy-quattro/ from upstream (pinned) -----------------
# Clone only when absent — an existing checkout is left untouched so upstream
# bumps stay deliberate (re-clone by deleting the dir, or bump
# OMARCHY_UPSTREAM_REF, then re-run). Runs as the invoking user, before the
# sudo re-exec below.
ensure_upstream() {
	local dir="$REPO_DIR/omarchy-quattro" tmp
	if [ -e "$dir/.git" ]; then
		echo ":: omarchy-quattro/ present ($(git -C "$dir" describe --tags --always 2>/dev/null || echo unknown)) — keeping"
		return 0
	fi
	command -v git >/dev/null 2>&1 || { echo "!! git not found — cannot fetch upstream" >&2; exit 1; }
	echo ":: cloning $UPSTREAM_URL @ $UPSTREAM_REF -> omarchy-quattro/"
	tmp="$dir.tmp.$$"
	rm -rf "$tmp"
	if ! git clone --depth 1 --branch "$UPSTREAM_REF" "$UPSTREAM_URL" "$tmp" 2>/dev/null; then
		echo ":: '$UPSTREAM_REF' is not a branch/tag — full clone + checkout"
		rm -rf "$tmp"
		git clone "$UPSTREAM_URL" "$tmp"
		git -C "$tmp" checkout --detach "$UPSTREAM_REF"
	fi
	mkdir -p "$dir"
	( shopt -s dotglob nullglob; mv "$tmp"/* "$dir"/ )
	rm -rf "$tmp"
	if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
		chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$dir"
	fi
	echo ":: omarchy-quattro/ ready ($(git -C "$dir" describe --tags --always 2>/dev/null || echo "$UPSTREAM_REF"))"
}
ensure_upstream

# --- become root for apt -------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
	echo "setup.sh needs root for apt — re-running under sudo…"
	exec sudo -E "$0" "$@"
fi

TARGET_USER="${SUDO_USER:-root}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

echo "========================================================================"
echo "Omaxian dependency setup"
echo "  repo:        $REPO_DIR"
echo "  install for: $TARGET_USER ($TARGET_HOME)"
echo "========================================================================"

# --- package sets -----------------------------------------------------------
# Hard-required: without one of these something core (bar, session, input
# focus, theming, audio/brightness keys, lock, notifications) does not work.
REQUIRED=(
	# bootstrap
	git ca-certificates curl jq
	# window manager, compositor, display manager, session bus
	i3-wm picom lightdm dbus-x11
	x11-utils x11-xserver-utils x11-xkb-utils
	# terminal + notifications
	kitty dunst libnotify-bin
	# network / bluetooth / audio / power / brightness
	network-manager bluez rfkill pulseaudio-utils brightnessctl upower
	# wallpaper, lock, idle
	feh hsetroot i3lock xss-lock
	# launcher window-raise, clipboard, live GTK theme push
	xdotool xclip xsettingsd
	# python input-focus helper + third-party plugin live watch
	python3 python3-xlib inotify-tools
	# polkit agent for pkexec prompts
	mate-polkit
	# process/query tools the scripts shell out to
	psmisc procps xdg-user-dirs
	# QML modules Quickshell plugins import (tray/media/wallpapers/FolderPicker)
	qml6-module-qt-labs-folderlistmodel
	qml6-module-qtquick-effects
	# fonts + icons
	fontconfig fonts-jetbrains-mono fonts-noto-color-emoji papirus-icon-theme
)

# Recommended: every widget/panel people actually use.
RECOMMENDED=(
	# media keys / MPRIS (omaxian.media). MPD stack omitted — `mpd` postinst
	# fails on Devuan/sysvinit; install mpd/mpdris2/mpc yourself if wanted.
	playerctl
	# screenshots + viewer + `convert` for the colour-picker swatch
	maim flameshot viewnior imagemagick
	# managers opened by widgets
	thunar blueman network-manager-gnome nm-connection-editor
	# battery %, Wi-Fi QR, colour picker, night light
	acpi qrencode gpick redshift
	# power manager started by i3_autostart
	xfce4-power-manager
	# fancy locker + Intel backlight path + `light` fallback
	i3lock-fancy xbacklight light
	# bar keyboard-layout click-to-cycle (falls back to xdotool / setxkbmap)
	xkb-switch
)

# Optional: hardware- or host-specific; nothing breaks without them.
OPTIONAL=(
	spice-vdagent          # VM clipboard sharing + display auto-resize
	radeontop              # AMD GPU load in omaxian.sysstats (scripts/gpu.sh)
	intel-gpu-tools        # Intel GPU load via intel_gpu_top (same script)
	# NVIDIA: nvidia-smi comes with the proprietary driver package, not listed here
	power-profiles-daemon  # omarchy-powerprofiles-* (needs D-Bus; works w/ elogind)
	openresolv             # lets omarchy-dns flush the resolver cache
	wireplumber            # wpctl fallback when pactl is absent
)

# No systemd (Devuan / sysvinit Debian): pull elogind so loginctl / xss-lock /
# the locker's session hooks work. On systemd hosts logind already provides it.
if [ ! -d /run/systemd/system ]; then
	REQUIRED+=(elogind libpam-elogind)
fi

# --- resolve + install ----------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive

echo ":: apt-get update"
apt-get update -qq

PKGS=("${REQUIRED[@]}")
if (( WITH_RECOMMENDED )); then PKGS+=("${RECOMMENDED[@]}"); fi
if (( WITH_OPTIONAL ));    then PKGS+=("${OPTIONAL[@]}");    fi

# Quickshell is only in Debian trixie (13) and newer — not in Devuan daedalus.
# Track it for the closing summary rather than aborting.
QUICKSHELL_OK=1
if apt-cache show quickshell >/dev/null 2>&1; then
	PKGS+=(quickshell)
else
	QUICKSHELL_OK=0
fi

# Drop anything this suite doesn't ship; report it once.
AVAIL=()
MISSING=()
UNINSTALLABLE=()
while read -r p; do
	[ -n "$p" ] || continue
	if apt-cache show "$p" >/dev/null 2>&1; then
		# Some suites can briefly expose a package whose exact-version deps are no
		# longer satisfiable against the currently installed security updates
		# (observed with rfkill on Devuan Excalibur). Skip those instead of aborting
		# the whole bootstrap; the summary calls them out for manual follow-up.
		if apt-get install -s "$p" >/dev/null 2>&1; then
			AVAIL+=("$p")
		else
			UNINSTALLABLE+=("$p")
		fi
	else
		MISSING+=("$p")
	fi
done < <(printf '%s\n' "${PKGS[@]}" | sort -u)

echo ":: installing ${#AVAIL[@]} packages"
apt-get install -y "${AVAIL[@]}"

# --- session D-Bus (Quickshell must reach the bus) -----------------------------
OPTS=/etc/X11/Xsession.options
if [ -f "$OPTS" ]; then
	if ! grep -qxF 'use-session-dbus' "$OPTS"; then
		echo 'use-session-dbus' >> "$OPTS"
		echo ":: enabled use-session-dbus in $OPTS"
	fi
else
	cat > "$OPTS" <<-'EOF'
	allow-failsafe
	allow-user-modmap
	allow-user-resources
	allow-user-xsession
	use-ssh-agent
	use-session-dbus
	EOF
	echo ":: created $OPTS with use-session-dbus"
fi

# --- bundled fonts (JetBrainsMono/Iosevka Nerd, Weather Icons, Feather) --------
FONT_SRC="$REPO_DIR/omaxian/.local/share/fonts"
if [ -d "$FONT_SRC" ] && [ "$TARGET_USER" != root ]; then
	FONT_DST="$TARGET_HOME/.local/share/fonts"
	TARGET_GROUP="$(id -gn "$TARGET_USER")"
	install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$FONT_DST"
	cp -r "$FONT_SRC/." "$FONT_DST/"
	chown -R "$TARGET_USER:$TARGET_GROUP" "$FONT_DST"
	sudo -u "$TARGET_USER" fc-cache -f >/dev/null 2>&1 || true
	echo ":: installed bundled fonts into $FONT_DST"
fi

# --- optional: deploy the port ------------------------------------------------
if (( RUN_DEPLOY )); then
	if [ "$TARGET_USER" = root ]; then
		echo "!! --deploy skipped: run ./install.sh && ./deploy.sh as your user, not root" >&2
	else
		echo ":: running install.sh + deploy.sh as $TARGET_USER"
		sudo -u "$TARGET_USER" -H bash -c "cd '$REPO_DIR' && ./install.sh && ./deploy.sh"
	fi
fi

# --- summary ----------------------------------------------------------------
echo "========================================================================"
echo "Done."
if (( ! QUICKSHELL_OK )); then
	echo
	echo "  ! 'quickshell' is not in this suite's apt (Debian < 13 / Devuan)."
	echo "    Build it from https://quickshell.org/docs/guide/install/ — the bar"
	echo "    will not start without it."
fi
if [ "${#MISSING[@]}" -gt 0 ]; then
	echo
	echo "  ! not found in apt, install by hand if you want the feature:"
	printf '      %s\n' "${MISSING[@]}"
fi
if [ "${#UNINSTALLABLE[@]}" -gt 0 ]; then
	echo
	echo "  ! present in apt but not currently installable on this system:"
	printf '      %s\n' "${UNINSTALLABLE[@]}"
	echo "    setup.sh skipped them so the rest of the install could continue."
fi
echo
if (( ! RUN_DEPLOY )); then
	echo "  Next:  cd $REPO_DIR && ./install.sh && ./deploy.sh"
fi
echo "  Then:  pick the Omaxian/i3 session in lightdm and log in fresh"
echo "         (a full login, not 'i3 restart' — see README §4)."
echo "========================================================================"
