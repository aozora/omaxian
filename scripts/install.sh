#!/bin/bash
# install.sh — seed ~/.local/share/omarchy and ~/.config/omarchy from this
# repo. Idempotent for the dock settings file; themes/default/bin are always
# refreshed from upstream + the port. Does NOT deploy i3/QS dotfiles — that
# is deploy.sh.
#
# Layout (do not confuse these):
#   ~/.local/share/omarchy/themes/   ← upstream themes + Omaxian overlays (nebula-ridge, …)
#   ~/.local/share/omarchy/default/  ← upstream themed/*.tpl templates
#   ~/.local/share/omarchy/bin/      ← omaxian-ported omarchy-* commands
#   ~/.config/omarchy/themes/        ← user overrides only (empty by design)
#   ~/.config/omarchy/themed/        ← created empty; deploy.sh fills *.tpl
#
#   ./scripts/install.sh
#   OMARCHY_UPSTREAM_URL=… OMARCHY_UPSTREAM_REF=… ./scripts/install.sh
#
# Must run as the login user (paths under that user's home). If invoked via
# sudo, re-execs as $SUDO_USER so themes do not land in /root/.
# Prefer ./omaxian-install.sh for first-time setup (TUI). Root ./install.sh is a shim.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ui.sh
source "$SCRIPT_DIR/lib/ui.sh"

# --- resolve install target (never seed root's home by accident) -------------
if [ "$(id -u)" -eq 0 ]; then
	if [ -z "${SUDO_USER:-}" ] || [ "$SUDO_USER" = root ]; then
		omaxian_err "refuse to install as root — run:  ./scripts/install.sh"
		echo "   (or:  sudo -u \$USER -H ./scripts/install.sh)" >&2
		exit 1
	fi
	omaxian_msg "re-exec as $SUDO_USER (was root via sudo)"
	exec sudo -u "$SUDO_USER" -H "$0" "$@"
fi

TARGET_HOME="${HOME}"
OMARCHY_SHARE="$TARGET_HOME/.local/share/omarchy"
OMARCHY_CONFIG="$TARGET_HOME/.config/omarchy"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Upstream Omarchy is not vendored — it is cloned into omarchy-quattro/ (pinned).
# Override either with an env var: OMARCHY_UPSTREAM_URL=… OMARCHY_UPSTREAM_REF=…
UPSTREAM_URL="${OMARCHY_UPSTREAM_URL:-https://github.com/omacom/omarchy.git}"
UPSTREAM_REF="${OMARCHY_UPSTREAM_REF:-v4.5.0-rc2}"

omaxian_banner
omaxian_msg "install  $(id -un)  $TARGET_HOME"
omaxian_info "repo $REPO_DIR"
omaxian_info "upstream $UPSTREAM_URL @ $UPSTREAM_REF"

# --- step 1: populate omarchy-quattro/ from upstream --------------------------
# Clone only when absent — an existing checkout is left untouched so upstream
# bumps stay deliberate (re-clone by deleting the dir, or bump
# OMARCHY_UPSTREAM_REF, then re-run). Either way we continue to step 2.
omaxian_phase "1/4  upstream Omarchy"
UPSTREAM_DIR="$REPO_DIR/omarchy-quattro"
if [ -e "$UPSTREAM_DIR/.git" ]; then
	omaxian_info "omarchy-quattro/ kept ($(git -C "$UPSTREAM_DIR" describe --tags --always 2>/dev/null || echo unknown))"
else
	command -v git >/dev/null 2>&1 || { omaxian_err "git not found — cannot fetch upstream"; exit 1; }
	omaxian_info "cloning $UPSTREAM_REF → omarchy-quattro/"
	tmp="$UPSTREAM_DIR.tmp.$$"
	rm -rf "$tmp"
	if ! git clone --depth 1 --branch "$UPSTREAM_REF" "$UPSTREAM_URL" "$tmp" 2>/dev/null; then
		omaxian_info "'$UPSTREAM_REF' not a branch/tag — full clone + checkout"
		rm -rf "$tmp"
		git clone "$UPSTREAM_URL" "$tmp"
		git -C "$tmp" checkout --detach "$UPSTREAM_REF"
	fi
	mkdir -p "$UPSTREAM_DIR"
	( shopt -s dotglob nullglob; mv "$tmp"/* "$UPSTREAM_DIR"/ )
	rm -rf "$tmp"
	omaxian_info "ready ($(git -C "$UPSTREAM_DIR" describe --tags --always 2>/dev/null || echo "$UPSTREAM_REF"))"
fi

# --- step 2: sanity-check the checkout ---------------------------------------
omaxian_phase "2/4  verify layout"
if [ ! -d "$UPSTREAM_DIR/themes" ] || [ ! -d "$UPSTREAM_DIR/default" ]; then
	omaxian_err "omarchy-quattro/ has no themes/ or default/ — wrong upstream ref?"
	exit 1
fi
THEME_COUNT=$(find "$UPSTREAM_DIR/themes" -mindepth 1 -maxdepth 1 -type d | wc -l)
omaxian_info "themes/ ($THEME_COUNT) and default/ OK"

# --- step 3: refresh ~/.local/share/omarchy ----------------------------------
# themes + default come from upstream; bin/ comes from the omaxian port
# (X11-adapted wrappers). Always replace those three trees so a re-run picks
# up upstream bumps and port changes; leave the rest of the share dir alone.
#
# ~/.config/omarchy/themes stays empty here on purpose — that dir is for
# user-installed overrides (omarchy-theme-list merges it with the share tree).
omaxian_phase "3/4  seed share"
mkdir -p "$OMARCHY_SHARE" "$OMARCHY_CONFIG"/{themes,themed}
rm -rf "$OMARCHY_SHARE"/{themes,default,bin}

cp -r "$UPSTREAM_DIR/themes" "$OMARCHY_SHARE/themes"
INSTALLED=$(find "$OMARCHY_SHARE/themes" -mindepth 1 -maxdepth 1 -type d | wc -l)

# Omaxian-only themes (e.g. nebula-ridge, the default) live under the port tree
# and are not in upstream. Overlay them so install alone (before deploy) still
# has the first-run theme.
PORT_THEMES="$REPO_DIR/omaxian/.local/share/omarchy/themes"
if [ -d "$PORT_THEMES" ]; then
	PORT_THEME_COUNT=0
	for theme_dir in "$PORT_THEMES"/*/; do
		[ -d "$theme_dir" ] || continue
		name=$(basename "$theme_dir")
		rm -rf "$OMARCHY_SHARE/themes/$name"
		cp -r "$theme_dir" "$OMARCHY_SHARE/themes/$name"
		PORT_THEME_COUNT=$((PORT_THEME_COUNT + 1))
	done
	if [ "$PORT_THEME_COUNT" -gt 0 ]; then
		INSTALLED=$(find "$OMARCHY_SHARE/themes" -mindepth 1 -maxdepth 1 -type d | wc -l)
		omaxian_info "themes $INSTALLED (incl. $PORT_THEME_COUNT port)"
	else
		omaxian_info "themes $INSTALLED"
	fi
else
	omaxian_info "themes $INSTALLED"
fi

cp -r "$UPSTREAM_DIR/default" "$OMARCHY_SHARE/default"

# Overlay the Devuan/X11 menu definition. Upstream's JSONC is Arch/Hyprland
# (Install/Remove/AUR/…). User extensions cannot delete items, so this
# replaces the file the omarchy.menu plugin reads.
PORT_MENU="$REPO_DIR/omaxian/.local/share/omarchy/default/omarchy/omarchy-menu.jsonc"
if [ -f "$PORT_MENU" ]; then
	mkdir -p "$OMARCHY_SHARE/default/omarchy"
	cp "$PORT_MENU" "$OMARCHY_SHARE/default/omarchy/omarchy-menu.jsonc"
fi

# Replace Arch/Hyprland end-user agent skills with the Omaxian set
# (i3, apt, maim, no uwsm). deploy.sh also copies this tree.
PORT_AGENTS="$REPO_DIR/omaxian/.local/share/omarchy/default/agents"
if [ -d "$PORT_AGENTS" ]; then
	rm -rf "$OMARCHY_SHARE/default/agents"
	cp -r "$PORT_AGENTS" "$OMARCHY_SHARE/default/agents"
fi

cp -r "$REPO_DIR/omaxian/.local/share/omarchy/bin" "$OMARCHY_SHARE/bin"
omaxian_info "default/ + bin/ + menu/agents overlays"

if [ "$INSTALLED" -eq 0 ]; then
	omaxian_err "no themes landed in $OMARCHY_SHARE/themes — aborting"
	exit 1
fi

# --- step 4: seed dock settings (once) ---------------------------------------
# docs/dock.md — write defaults only when missing so a reinstall never
# clobbers an existing customization.
omaxian_phase "4/4  dock settings"
DOCK_SETTINGS="$OMARCHY_CONFIG/dock-settings.json"
if [ ! -f "$DOCK_SETTINGS" ]; then
	cat > "$DOCK_SETTINGS" <<'EOF'
{
  "fullWidth": false,
  "roundedCorners": true,
  "hoverAnimation": true
}
EOF
	omaxian_info "wrote defaults"
else
	omaxian_info "kept existing"
fi

omaxian_done "install done — $INSTALLED themes → $OMARCHY_SHARE"
if [[ ${OMAXIAN_NESTED:-0} != 1 ]]; then
	omaxian_info "next: ./scripts/deploy.sh"
fi
