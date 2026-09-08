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
# ~/.xsessionrc is load-bearing: the display manager → /etc/X11/Xsession sources it
# *before* i3, so i3 and every keybind inherit $OMARCHY_PATH/bin on PATH.
# A full logout/login is required after the first deploy (i3 restart keeps
# the old environment).
#
# LIVE SESSION SAFETY: while i3 is up this script (1) raises a deploy lock so
# Quickshell ignores FileView / plugin churn, (2) stops picom before any
# copy — glx + live bar rebuild freezes X, (3) never runs i3-msg reload or
# omarchy-restart-shell. QML applies on the next login.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/omaxian"
DEPLOY_LOCK="${XDG_RUNTIME_DIR:-/tmp}/omaxian-deploy.lock"
COMP="$HOME/.config/i3/scripts/i3_comp"
LIVE_SESSION=0

if [ "$(id -u)" -eq 0 ]; then
	echo "!! refuse to deploy as root — run:  ./deploy.sh" >&2
	exit 1
fi

if [ ! -d "$SRC/.config" ] || [ ! -d "$SRC/.local/share" ]; then
	echo "!! missing $SRC/{.config,.local/share} — wrong checkout?" >&2
	exit 1
fi

if command -v i3-msg >/dev/null 2>&1 && i3-msg -t get_version >/dev/null 2>&1; then
	LIVE_SESSION=1
fi

echo "========================================================================"
echo "Deploying Omaxian"
echo "  user: $(id -un) ($HOME)"
echo "  from: $SRC"
if (( LIVE_SESSION )); then
	echo "  mode: LIVE i3 — picom paused; shell file-reload frozen; no reload/restart"
fi
echo "========================================================================"

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
	echo ":: stopping picom for safe copy (glx + live shell churn freezes X)"
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
		echo ":: picom restarted"
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

echo
echo "-- 1/4  ~/.config -------------------------------------------------------"
copy_tree "$SRC/.config" "$HOME/.config"
echo ":: copied $SRC/.config/ -> $HOME/.config/ (rsync/atomic)"

echo
echo "-- 2/4  ~/.local/share --------------------------------------------------"
copy_tree "$SRC/.local/share" "$HOME/.local/share"
echo ":: copied $SRC/.local/share/ -> $HOME/.local/share/ (rsync/atomic)"
if [ -d "$HOME/.local/share/omarchy/shell" ]; then
	echo ":: shell present: $HOME/.local/share/omarchy/shell"
else
	echo "!! $HOME/.local/share/omarchy/shell missing after copy" >&2
	exit 1
fi
# install.sh seeds upstream default/agents (Hyprland skill). Replace that
# leftover once the port's omaxian skill is in place — rsync does not delete.
if [ -d "$HOME/.local/share/omarchy/default/agents/skills/omaxian" ]; then
	rm -rf "$HOME/.local/share/omarchy/default/agents/skills/omarchy"
	echo ":: dropped upstream default/agents/skills/omarchy"
fi

# Stock shell.json lives under share ($OMARCHY_PATH/shell.json). The live
# user file is ~/.config/omarchy/shell.json (Settings / bar layout). Seed
# once when missing so redeploy never wipes widget options or layout edits.
USER_SHELL_JSON="$HOME/.config/omarchy/shell.json"
DEFAULT_SHELL_JSON="$HOME/.local/share/omarchy/shell.json"
mkdir -p "$HOME/.config/omarchy" "$HOME/.local/state/omarchy"
if [[ -f $USER_SHELL_JSON ]]; then
	# Preserve a copy before any later tooling touches Settings — never
	# overwrite the live file here, only refresh the backup.
	cp -a "$USER_SHELL_JSON" "$HOME/.local/state/omarchy/shell.json.bak"
	echo ":: kept existing $USER_SHELL_JSON (Settings / user layout)"
	echo ":: backup -> $HOME/.local/state/omarchy/shell.json.bak"
elif [[ -f $DEFAULT_SHELL_JSON ]]; then
	cp -a "$DEFAULT_SHELL_JSON" "$USER_SHELL_JSON"
	cp -a "$USER_SHELL_JSON" "$HOME/.local/state/omarchy/shell.json.bak"
	echo ":: seeded $USER_SHELL_JSON from defaults"
else
	echo "!! missing stock defaults: $DEFAULT_SHELL_JSON" >&2
	exit 1
fi

echo
echo "-- 3/4  ~/.xsessionrc (OMARCHY_PATH + PATH) -----------------------------"
cp "$SRC/.xsessionrc" "$HOME/.xsessionrc.tmp"
mv -f "$HOME/.xsessionrc.tmp" "$HOME/.xsessionrc"
echo ":: wrote $HOME/.xsessionrc"
echo "::   OMARCHY_PATH=\$HOME/.local/share/omarchy"
echo "::   PATH=\$OMARCHY_PATH/bin:… (prepended)"

echo
echo "-- 4/4  ~/.icons --------------------------------------------------------"
if [ -d "$SRC/.icons" ]; then
	mkdir -p "$HOME/.icons"
	if command -v rsync >/dev/null 2>&1; then
		rsync -a -- "$SRC/.icons/" "$HOME/.icons/"
	else
		cp -a "$SRC/.icons/." "$HOME/.icons/"
	fi
	echo ":: copied icons -> $HOME/.icons"
else
	echo ":: no .icons/ in tree — skipped"
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

echo
echo "========================================================================"
echo "Deployment done."
echo
echo "  Verify:"
echo "    test -f ~/.xsessionrc && grep OMARCHY_PATH ~/.xsessionrc"
echo "    ls ~/.local/share/omarchy/bin/omarchy-launch-shell"
echo
if (( LIVE_SESSION )); then
	echo "  LIVE session: files are on disk. Do NOT run omarchy-restart-shell"
	echo "  or i3-msg reload from an agent just to 'apply' — that used to"
	echo "  freeze X. QML/bar: log out and back in. Binds only (optional):"
	echo "    i3-msg reload"
else
	echo "  Log out/in so i3 inherits PATH (first install)."
fi
echo "========================================================================"
