#!/bin/bash
# bootstrap.sh — curl|bash entry for a first-time Omaxian install.
#
#   curl -fsSL https://raw.githubusercontent.com/aozora/omaxian/main/bootstrap.sh | bash
#
# Env overrides:
#   OMAXIAN_DIR   clone destination (default: ~/projects/omaxian)
#   OMAXIAN_REF   git ref to clone (default: main)
#   OMAXIAN_REPO  git URL (default: https://github.com/aozora/omaxian.git)
#
# Hands off to omaxian-install.sh in the clone (TUI). Never seeds /root.

set -euo pipefail

OMAXIAN_REPO="${OMAXIAN_REPO:-https://github.com/aozora/omaxian.git}"
OMAXIAN_REF="${OMAXIAN_REF:-main}"
OMAXIAN_DIR="${OMAXIAN_DIR:-$HOME/projects/omaxian}"

if [ "$(id -u)" -eq 0 ]; then
	if [ -z "${SUDO_USER:-}" ] || [ "$SUDO_USER" = root ]; then
		echo "!! refuse to bootstrap as root — run as your login user" >&2
		echo "   curl -fsSL …/bootstrap.sh | bash" >&2
		exit 1
	fi
	# File on disk: re-exec as the invoking user. Piped via `sudo bash`: refuse
	# (stdin is already consumed); run the curl one-liner without sudo instead.
	if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
		echo ":: re-exec as $SUDO_USER"
		exec sudo -u "$SUDO_USER" -H env \
			OMAXIAN_REPO="$OMAXIAN_REPO" \
			OMAXIAN_REF="$OMAXIAN_REF" \
			OMAXIAN_DIR="$OMAXIAN_DIR" \
			bash "${BASH_SOURCE[0]}"
	fi
	echo "!! do not pipe bootstrap.sh to sudo bash — run as your user:" >&2
	echo "   curl -fsSL …/bootstrap.sh | bash" >&2
	exit 1
fi

ensure_git() {
	if command -v git >/dev/null 2>&1; then
		return 0
	fi
	echo ":: git not found — installing…"
	sudo apt-get install -y git || {
		echo "!! install git (apt install git) and re-run" >&2
		exit 1
	}
}

looks_like_omaxian() {
	local dir="$1"
	[ -f "$dir/omaxian-install.sh" ] && [ -d "$dir/omaxian" ] && [ -d "$dir/scripts" ]
}

ensure_git

if looks_like_omaxian "$OMAXIAN_DIR"; then
	echo ":: reusing existing checkout at $OMAXIAN_DIR"
else
	if [ -e "$OMAXIAN_DIR" ] && [ ! -d "$OMAXIAN_DIR/.git" ]; then
		echo "!! $OMAXIAN_DIR exists but does not look like an Omaxian checkout" >&2
		echo "   set OMAXIAN_DIR to an empty path or an existing clone" >&2
		exit 1
	fi
	parent="$(dirname "$OMAXIAN_DIR")"
	mkdir -p "$parent"
	if [ -d "$OMAXIAN_DIR/.git" ]; then
		echo ":: $OMAXIAN_DIR is a git repo but missing omaxian-install.sh — check OMAXIAN_REF / pull"
		exit 1
	fi
	echo ":: cloning $OMAXIAN_REPO @ $OMAXIAN_REF → $OMAXIAN_DIR"
	tmp="$OMAXIAN_DIR.tmp.$$"
	rm -rf "$tmp"
	if ! git clone --depth 1 --branch "$OMAXIAN_REF" "$OMAXIAN_REPO" "$tmp" 2>/dev/null; then
		echo ":: '$OMAXIAN_REF' is not a branch/tag — full clone + checkout"
		rm -rf "$tmp"
		git clone "$OMAXIAN_REPO" "$tmp"
		git -C "$tmp" checkout --detach "$OMAXIAN_REF"
	fi
	mv "$tmp" "$OMAXIAN_DIR"
fi

if ! looks_like_omaxian "$OMAXIAN_DIR"; then
	echo "!! clone at $OMAXIAN_DIR is missing omaxian-install.sh — wrong ref?" >&2
	exit 1
fi

chmod +x "$OMAXIAN_DIR/omaxian-install.sh" 2>/dev/null || true
echo ":: starting omaxian-install.sh"
exec "$OMAXIAN_DIR/omaxian-install.sh"
