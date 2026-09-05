#!/bin/bash
# deploy.sh — copy the omaxian/ port into the live home directory.
# Run as the login user after ./install.sh. Idempotent overwrite.
#
#   ./deploy.sh
#
# Installs:
#   omaxian/.config/*              → ~/.config/
#   omaxian/.local/share/*         → ~/.local/share/  (shell/, fonts/, …)
#   omaxian/.xsessionrc            → ~/.xsessionrc    (OMARCHY_PATH + PATH)
#   omaxian/.icons                 → ~/.icons/
#
# ~/.xsessionrc is load-bearing: lightdm → /etc/X11/Xsession sources it
# *before* i3, so i3 and every keybind inherit $OMARCHY_PATH/bin on PATH.
# A full logout/login is required after the first deploy (i3 restart keeps
# the old environment).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/omaxian"

if [ "$(id -u)" -eq 0 ]; then
	echo "!! refuse to deploy as root — run:  ./deploy.sh" >&2
	exit 1
fi

if [ ! -d "$SRC/.config" ] || [ ! -d "$SRC/.local/share" ]; then
	echo "!! missing $SRC/{.config,.local/share} — wrong checkout?" >&2
	exit 1
fi

echo "========================================================================"
echo "Deploying Omaxian"
echo "  user: $(id -un) ($HOME)"
echo "  from: $SRC"
echo "========================================================================"

echo
echo "-- 1/4  ~/.config -------------------------------------------------------"
mkdir -p "$HOME/.config"
cp -r "$SRC/.config/"* "$HOME/.config/"
echo ":: copied $SRC/.config/* -> $HOME/.config/"

echo
echo "-- 2/4  ~/.local/share --------------------------------------------------"
mkdir -p "$HOME/.local/share"
cp -r "$SRC/.local/share/"* "$HOME/.local/share/"
echo ":: copied $SRC/.local/share/* -> $HOME/.local/share/"
if [ -d "$HOME/.local/share/omarchy/shell" ]; then
	echo ":: shell present: $HOME/.local/share/omarchy/shell"
else
	echo "!! $HOME/.local/share/omarchy/shell missing after copy" >&2
	exit 1
fi
# install.sh seeds upstream default/agents (Hyprland skill). Replace that
# leftover once the port's omaxian skill is in place — cp -r does not delete.
if [ -d "$HOME/.local/share/omarchy/default/agents/skills/omaxian" ]; then
	rm -rf "$HOME/.local/share/omarchy/default/agents/skills/omarchy"
	echo ":: dropped upstream default/agents/skills/omarchy"
fi

# Stock shell.json lives under share ($OMARCHY_PATH/shell.json). The live
# user file is ~/.config/omarchy/shell.json (Settings / bar layout). Seed
# once when missing so redeploy never wipes widget options or layout edits.
USER_SHELL_JSON="$HOME/.config/omarchy/shell.json"
DEFAULT_SHELL_JSON="$HOME/.local/share/omarchy/shell.json"
mkdir -p "$HOME/.config/omarchy"
if [[ ! -f $USER_SHELL_JSON ]]; then
	if [[ ! -f $DEFAULT_SHELL_JSON ]]; then
		echo "!! missing stock defaults: $DEFAULT_SHELL_JSON" >&2
		exit 1
	fi
	cp -a "$DEFAULT_SHELL_JSON" "$USER_SHELL_JSON"
	echo ":: seeded $USER_SHELL_JSON from defaults"
else
	echo ":: kept existing $USER_SHELL_JSON (Settings / user layout)"
fi

echo
echo "-- 3/4  ~/.xsessionrc (OMARCHY_PATH + PATH) -----------------------------"
# Sourced by /etc/X11/Xsession before i3 starts — without it i3 (and every
# keybind exec) runs with no OMARCHY_PATH and no ~/.local/share/omarchy/bin
# on PATH. The Quickshell host also exports these itself, but terminals and
# keybinds still need this file.
cp "$SRC/.xsessionrc" "$HOME/.xsessionrc"
echo ":: wrote $HOME/.xsessionrc"
echo "::   OMARCHY_PATH=\$HOME/.local/share/omarchy"
echo "::   PATH=\$OMARCHY_PATH/bin:… (prepended)"

echo
echo "-- 4/4  ~/.icons --------------------------------------------------------"
if [ -d "$SRC/.icons" ]; then
	mkdir -p "$HOME/.icons"
	cp -r "$SRC/.icons/"* "$HOME/.icons/" 2>/dev/null || cp -r "$SRC/.icons" "$HOME/"
	echo ":: copied icons -> $HOME/.icons"
else
	echo ":: no .icons/ in tree — skipped"
fi

echo
echo "========================================================================"
echo "Deployment done."
echo
echo "  Verify (this shell may still lack PATH until re-login):"
echo "    test -f ~/.xsessionrc && grep OMARCHY_PATH ~/.xsessionrc"
echo "    ls ~/.local/share/omarchy/bin/omarchy-launch-shell"
echo "    ls ~/.config/omarchy/shell.json"
echo
echo "  Then:  full logout/login (not 'i3 restart') so i3 inherits PATH."
echo "========================================================================"
