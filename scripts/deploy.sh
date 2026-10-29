#!/bin/bash
# deploy.sh — copy the omaxian/ port into the live home directory.
# Run as the login user after ./scripts/install.sh. Idempotent overwrite.
#
#   ./scripts/deploy.sh
#
# Installs:
#   omaxian/.config/*              → ~/.config/
#   omaxian/.local/share/*         → ~/.local/share/  (shell/, fonts/, …)
#   omaxian/.xsessionrc            → ~/.xsessionrc    (OMARCHY_PATH + PATH)
#   omaxian/.icons                 → ~/.icons/
#
# ~/.xsessionrc is load-bearing: the display manager → /etc/X11/Xsession sources it
# *before* i3, so i3 and every keybind inherit $OMARCHY_PATH/bin on PATH.
# A full logout/login is required after the first deploy (i3 restart keeps
# the old environment).
#
# LIVE SESSION SAFETY: while i3 is up this script (1) raises a deploy lock so
# Quickshell ignores FileView / plugin churn, (2) stops picom before any
# copy — glx + live bar rebuild freezes X, (3) never runs i3-msg reload or
# omarchy-restart-shell. QML applies on the next login.
#
# Prefer ./omaxian-install.sh for first-time setup (TUI). Root ./deploy.sh is a shim.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ui.sh
source "$SCRIPT_DIR/lib/ui.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO_DIR/omaxian"
DEPLOY_LOCK="${XDG_RUNTIME_DIR:-/tmp}/omaxian-deploy.lock"
COMP="$HOME/.config/i3/scripts/i3_comp"
LIVE_SESSION=0

if [ "$(id -u)" -eq 0 ]; then
	omaxian_err "refuse to deploy as root — run:  ./scripts/deploy.sh"
	exit 1
fi

if [ ! -d "$SRC/.config" ] || [ ! -d "$SRC/.local/share" ]; then
	omaxian_err "missing $SRC/{.config,.local/share} — wrong checkout?"
	exit 1
fi

if command -v i3-msg >/dev/null 2>&1 && i3-msg -t get_version >/dev/null 2>&1; then
	LIVE_SESSION=1
fi

omaxian_banner
omaxian_msg "deploy  $(id -un)  $HOME"
omaxian_info "from $SRC"
if (( LIVE_SESSION )); then
	omaxian_info "LIVE i3 — picom paused; no reload/restart"
fi

# Copy a tree without truncating files a live process still has open.
# `cp -r` opens the destination O_TRUNC; long-running bash (i3_display_watch,
# omarchy-launch-shell) then reads the next line from the new inode at a
# stale offset and can run garbage (including xrandr --off). rsync writes a
# temp file and renames, so those processes keep the old inode. It also
# skips unchanged files.
copy_tree() {
	local src="$1" dst="$2"
	mkdir -p "$dst"
	if command -v rsync >/dev/null 2>&1; then
		rsync -a -- "$src/" "$dst/"
		return
	fi
	python3 - "$src" "$dst" <<'PY'
import os, shutil, sys, tempfile
src, dst = sys.argv[1], sys.argv[2]
for root, dirs, files in os.walk(src):
    rel = os.path.relpath(root, src)
    dest_dir = dst if rel == os.curdir else os.path.join(dst, rel)
    os.makedirs(dest_dir, exist_ok=True)
    for name in files:
        s = os.path.join(root, name)
        d = os.path.join(dest_dir, name)
        fd, tmp = tempfile.mkstemp(prefix=".deploy-", dir=dest_dir)
        os.close(fd)
        try:
            shutil.copy2(s, tmp)
            os.replace(tmp, d)
        except Exception:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
PY
}

stop_picom() {
	pgrep -u "$UID" -x picom >/dev/null 2>&1 || return 0
	omaxian_info "stopping picom"
	pkill -u "$UID" -x picom 2>/dev/null || true
	local _
	for _ in $(seq 1 50); do
		pgrep -u "$UID" -x picom >/dev/null 2>&1 || return 0
		sleep 0.1
	done
	pkill -9 -u "$UID" -x picom 2>/dev/null || true
}

start_picom() {
	[[ -x $COMP ]] || return 0
	"$COMP" >/dev/null 2>&1 || true
	if pgrep -u "$UID" -x picom >/dev/null 2>&1; then
		omaxian_info "picom restarted"
	fi
}

cleanup_live() {
	rm -f "$DEPLOY_LOCK" 2>/dev/null || true
	if (( LIVE_SESSION )); then
		start_picom
	fi
}

if (( LIVE_SESSION )); then
	# Shell FileViews watch this path — create before any rsync so reload
	# handlers see deployFrozen and no-op.
	printf 'deploy\n' >"$DEPLOY_LOCK"
	trap cleanup_live EXIT
	# Give Quickshell's FileView a beat to notice the lock.
	sleep 0.4
	stop_picom
fi

omaxian_phase "1/4  ~/.config"
copy_tree "$SRC/.config" "$HOME/.config"
omaxian_info "copied"

omaxian_phase "2/4  ~/.local/share"
copy_tree "$SRC/.local/share" "$HOME/.local/share"
if [ ! -d "$HOME/.local/share/omarchy/shell" ]; then
	omaxian_err "$HOME/.local/share/omarchy/shell missing after copy"
	exit 1
fi
omaxian_info "shell OK"
# install.sh seeds upstream default/agents (Hyprland skill). Replace that
# leftover once the port's omaxian skill is in place — rsync does not delete.
if [ -d "$HOME/.local/share/omarchy/default/agents/skills/omarchy" ]; then
	rm -rf "$HOME/.local/share/omarchy/default/agents/skills/omarchy"
	omaxian_info "dropped upstream agents/skills/omarchy"
fi

# Stock shell.json lives under share ($OMARCHY_PATH/shell.json). The live
# user file is ~/.config/omarchy/shell.json (Settings / bar layout). Seed
# once when missing so redeploy never wipes widget options or layout edits.
USER_SHELL_JSON="$HOME/.config/omarchy/shell.json"
DEFAULT_SHELL_JSON="$HOME/.local/share/omarchy/shell.json"
mkdir -p "$HOME/.config/omarchy" "$HOME/.local/state/omarchy"
if [[ -f $USER_SHELL_JSON ]]; then
	cp -a "$USER_SHELL_JSON" "$HOME/.local/state/omarchy/shell.json.bak"
	omaxian_info "kept shell.json (Settings)"
elif [[ -f $DEFAULT_SHELL_JSON ]]; then
	cp -a "$DEFAULT_SHELL_JSON" "$USER_SHELL_JSON"
	cp -a "$USER_SHELL_JSON" "$HOME/.local/state/omarchy/shell.json.bak"
	omaxian_info "seeded shell.json"
else
	omaxian_err "missing stock defaults: $DEFAULT_SHELL_JSON"
	exit 1
fi

# Seed keyboard.json once from /etc/default/keyboard (Debian installer layout).
# Never overwrite an existing user file. Falls back to "us" inside the helper
# if the system file is missing.
USER_KEYBOARD_JSON="$HOME/.config/omarchy/keyboard.json"
KEYBOARD_APPLY="$HOME/.local/share/omarchy/bin/omarchy-keyboard-apply"
if [[ -f $USER_KEYBOARD_JSON ]]; then
	omaxian_info "kept keyboard.json"
elif [[ -x $KEYBOARD_APPLY ]]; then
	if "$KEYBOARD_APPLY" --seed-config; then
		omaxian_info "seeded keyboard.json"
	else
		omaxian_err "could not seed $USER_KEYBOARD_JSON"
	fi
else
	omaxian_err "missing omarchy-keyboard-apply — skip keyboard.json seed"
fi

omaxian_phase "3/4  ~/.xsessionrc"
cp "$SRC/.xsessionrc" "$HOME/.xsessionrc.tmp"
mv -f "$HOME/.xsessionrc.tmp" "$HOME/.xsessionrc"
omaxian_info "OMARCHY_PATH + PATH"

omaxian_phase "4/4  ~/.icons"
if [ -d "$SRC/.icons" ]; then
	mkdir -p "$HOME/.icons"
	if command -v rsync >/dev/null 2>&1; then
		rsync -a -- "$SRC/.icons/" "$HOME/.icons/"
	else
		cp -a "$SRC/.icons/." "$HOME/.icons/"
	fi
	omaxian_info "copied"
else
	omaxian_info "skipped (none in tree)"
fi

# A live i3 session already ran autostart. Seed the once-lock so a later
# `i3-msg reload` (binds only) never re-runs session daemons.
if (( LIVE_SESSION )) && [[ -n ${XDG_RUNTIME_DIR:-} ]]; then
	mkdir -p "$XDG_RUNTIME_DIR/omaxian-i3-autostart" || true
fi

# Drop deploy freeze, then bring picom back (trap also does this on EXIT).
if (( LIVE_SESSION )); then
	rm -f "$DEPLOY_LOCK"
	sleep 0.2
	start_picom
	trap - EXIT
fi

omaxian_done "deploy done"
if (( LIVE_SESSION )); then
	omaxian_info "QML/bar: log out and back in  ·  binds only: i3-msg reload"
else
	omaxian_info "log out/in so i3 inherits PATH (first install)"
fi
