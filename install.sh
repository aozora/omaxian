#!/bin/bash
# install.sh — seed ~/.local/share/omarchy and ~/.config/omarchy from this
# repo. Idempotent for the dock settings file; themes/default/bin are always
# refreshed from upstream + the port. Does NOT deploy i3/QS dotfiles — that
# is deploy.sh.
#
# Layout (do not confuse these):
#   ~/.local/share/omarchy/themes/   ← upstream themes (~120 MB) land HERE
#   ~/.local/share/omarchy/default/  ← upstream themed/*.tpl templates
#   ~/.local/share/omarchy/bin/      ← omaxian-ported omarchy-* commands
#   ~/.config/omarchy/themes/        ← user overrides only (empty by design)
#   ~/.config/omarchy/themed/        ← created empty; deploy.sh fills *.tpl
#
#   ./install.sh
#   OMARCHY_UPSTREAM_URL=… OMARCHY_UPSTREAM_REF=… ./install.sh
#
# Must run as the login user (paths under that user's home). If invoked via
# sudo, re-execs as $SUDO_USER so themes do not land in /root/.

set -euo pipefail

# --- resolve install target (never seed root's home by accident) -------------
if [ "$(id -u)" -eq 0 ]; then
	if [ -z "${SUDO_USER:-}" ] || [ "$SUDO_USER" = root ]; then
		echo "!! refuse to install as root — run:  ./install.sh" >&2
		echo "   (or:  sudo -u \$USER -H ./install.sh)" >&2
		exit 1
	fi
	echo ":: re-exec as $SUDO_USER (was root via sudo)"
	exec sudo -u "$SUDO_USER" -H "$0" "$@"
fi

TARGET_HOME="${HOME}"
OMARCHY_SHARE="$TARGET_HOME/.local/share/omarchy"
OMARCHY_CONFIG="$TARGET_HOME/.config/omarchy"

echo "========================================================================"
echo "Installing Omaxian"
echo "  user:   $(id -un) ($TARGET_HOME)"
echo "========================================================================"

# Repo root = the directory this script lives in, resolved so it works no
# matter where install.sh is invoked from.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo ":: repo: $REPO_DIR"

# Upstream Omarchy is not vendored — it is cloned into omarchy-quattro/ (pinned).
# Override either with an env var: OMARCHY_UPSTREAM_URL=… OMARCHY_UPSTREAM_REF=…
UPSTREAM_URL="${OMARCHY_UPSTREAM_URL:-https://github.com/omacom/omarchy.git}"
UPSTREAM_REF="${OMARCHY_UPSTREAM_REF:-v4.0.2}"
echo ":: upstream: $UPSTREAM_URL @ $UPSTREAM_REF"

# --- step 1: populate omarchy-quattro/ from upstream --------------------------
# Clone only when absent — an existing checkout is left untouched so upstream
# bumps stay deliberate (re-clone by deleting the dir, or bump
# OMARCHY_UPSTREAM_REF, then re-run). Either way we continue to step 2.
echo
echo "-- 1/4  upstream Omarchy checkout ---------------------------------------"
UPSTREAM_DIR="$REPO_DIR/omarchy-quattro"
if [ -e "$UPSTREAM_DIR/.git" ]; then
	echo ":: omarchy-quattro/ present ($(git -C "$UPSTREAM_DIR" describe --tags --always 2>/dev/null || echo unknown)) — keeping, continuing"
else
	command -v git >/dev/null 2>&1 || { echo "!! git not found — cannot fetch upstream" >&2; exit 1; }
	echo ":: cloning $UPSTREAM_URL @ $UPSTREAM_REF -> omarchy-quattro/"
	tmp="$UPSTREAM_DIR.tmp.$$"
	rm -rf "$tmp"
	if ! git clone --depth 1 --branch "$UPSTREAM_REF" "$UPSTREAM_URL" "$tmp" 2>/dev/null; then
		echo ":: '$UPSTREAM_REF' is not a branch/tag — full clone + checkout"
		rm -rf "$tmp"
		git clone "$UPSTREAM_URL" "$tmp"
		git -C "$tmp" checkout --detach "$UPSTREAM_REF"
	fi
	mkdir -p "$UPSTREAM_DIR"
	( shopt -s dotglob nullglob; mv "$tmp"/* "$UPSTREAM_DIR"/ )
	rm -rf "$tmp"
	echo ":: omarchy-quattro/ ready ($(git -C "$UPSTREAM_DIR" describe --tags --always 2>/dev/null || echo "$UPSTREAM_REF"))"
fi

# --- step 2: sanity-check the checkout ---------------------------------------
# themes/ and default/ are what we copy into ~/.local/share/omarchy; without
# them the rest of the install would produce an empty/broken share tree.
echo
echo "-- 2/4  verify omarchy-quattro/ layout ----------------------------------"
if [ ! -d "$UPSTREAM_DIR/themes" ] || [ ! -d "$UPSTREAM_DIR/default" ]; then
	echo "!! omarchy-quattro/ has no themes/ or default/ — wrong upstream ref?" >&2
	exit 1
fi
THEME_COUNT=$(find "$UPSTREAM_DIR/themes" -mindepth 1 -maxdepth 1 -type d | wc -l)
echo ":: themes/ ($THEME_COUNT themes) and default/ present"

# --- step 3: refresh ~/.local/share/omarchy ----------------------------------
# themes + default come from upstream; bin/ comes from the omaxian port
# (X11-adapted wrappers). Always replace those three trees so a re-run picks
# up upstream bumps and port changes; leave the rest of the share dir alone.
#
# ~/.config/omarchy/themes stays empty here on purpose — that dir is for
# user-installed overrides (omarchy-theme-list merges it with the share tree).
echo
echo "-- 3/4  seed $OMARCHY_SHARE ---------------------------------------------"
echo ":: ensuring share + config skeleton"
mkdir -p "$OMARCHY_SHARE" "$OMARCHY_CONFIG"/{themes,themed}

echo ":: replacing themes/ default/ bin/ under $OMARCHY_SHARE"
rm -rf "$OMARCHY_SHARE"/{themes,default,bin}

cp -r "$UPSTREAM_DIR/themes"  "$OMARCHY_SHARE/themes"    # ~120 MB
INSTALLED=$(find "$OMARCHY_SHARE/themes" -mindepth 1 -maxdepth 1 -type d | wc -l)
echo ":: copied $INSTALLED themes -> $OMARCHY_SHARE/themes"

	cp -r "$UPSTREAM_DIR/default" "$OMARCHY_SHARE/default"
	echo ":: copied default/ -> $OMARCHY_SHARE/default"

	# Overlay the Devuan/X11 menu definition. Upstream's JSONC is Arch/Hyprland
	# (Install/Remove/AUR/…). User extensions cannot delete items, so this
	# replaces the file the omarchy.menu plugin reads.
	PORT_MENU="$REPO_DIR/omaxian/.local/share/omarchy/default/omarchy/omarchy-menu.jsonc"
	if [ -f "$PORT_MENU" ]; then
		mkdir -p "$OMARCHY_SHARE/default/omarchy"
		cp "$PORT_MENU" "$OMARCHY_SHARE/default/omarchy/omarchy-menu.jsonc"
		echo ":: overlaid port omarchy-menu.jsonc"
	fi

	# Replace Arch/Hyprland end-user agent skills with the Omaxian set
	# (i3, apt, maim, no uwsm). deploy.sh also copies this tree.
	PORT_AGENTS="$REPO_DIR/omaxian/.local/share/omarchy/default/agents"
	if [ -d "$PORT_AGENTS" ]; then
		rm -rf "$OMARCHY_SHARE/default/agents"
		cp -r "$PORT_AGENTS" "$OMARCHY_SHARE/default/agents"
		echo ":: overlaid port default/agents/"
	fi

cp -r "$REPO_DIR/omaxian/.local/share/omarchy/bin" "$OMARCHY_SHARE/bin"
echo ":: copied bin/ (omaxian port) -> $OMARCHY_SHARE/bin"

echo ":: note: $OMARCHY_CONFIG/themes is for user overrides only (left empty)"

if [ "$INSTALLED" -eq 0 ]; then
	echo "!! no themes landed in $OMARCHY_SHARE/themes — aborting" >&2
	exit 1
fi

# --- step 4: seed dock settings (once) ---------------------------------------
# docs/dock.md — write defaults only when missing so a reinstall never
# clobbers an existing customization.
echo
echo "-- 4/4  dock settings ---------------------------------------------------"
DOCK_SETTINGS="$OMARCHY_CONFIG/dock-settings.json"
if [ ! -f "$DOCK_SETTINGS" ]; then
	echo ":: writing default $DOCK_SETTINGS"
	cat > "$DOCK_SETTINGS" <<'EOF'
{
  "fullWidth": false,
  "roundedCorners": true,
  "hoverAnimation": true
}
EOF
else
	echo ":: $DOCK_SETTINGS already present — keeping"
fi

echo
echo "========================================================================"
echo "Installation done."
echo "  themes:  $OMARCHY_SHARE/themes  ($INSTALLED)"
echo "  default: $OMARCHY_SHARE/default"
echo "  bin:     $OMARCHY_SHARE/bin"
echo "  Next:    ./deploy.sh   (i3 / Quickshell / \$HOME dotfiles)"
echo "========================================================================"
