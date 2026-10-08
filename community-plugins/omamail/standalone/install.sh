#!/bin/bash
# Installs the standalone Omamail launcher for the current user.
#   standalone/install.sh [--build-backend] [--claim-mailto] [--uninstall]
# Nothing is copied: ~/.local/share/omamail-app is a folder of symlinks into
# this checkout, so editing the plugin needs no reinstall.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin=$(dirname "$here")
: "${OMARCHY_PATH:=$HOME/.local/share/omarchy}"
data=${XDG_DATA_HOME:-$HOME/.local/share}
home=$data/omamail-app
bin=$HOME/.local/bin
apps=$data/applications

build=0
claim=0
uninstall=0
for arg in "$@"; do
  case $arg in
    --build-backend) build=1 ;;
    --claim-mailto) claim=1 ;;
    --uninstall) uninstall=1 ;;
    *) echo "usage: install.sh [--build-backend] [--claim-mailto] [--uninstall]" >&2; exit 2 ;;
  esac
done

if (( uninstall )); then
  rm -rf "$home" "$apps/omamail.desktop" "$bin/omamail-app" "$apps/omamail-app.desktop" "$data/icons/hicolor/scalable/apps/omamail.svg"
  echo "Removed standalone Omamail (accounts and backend in ~/.config/omamail, ~/.local/share/omamail are kept)."
  exit 0
fi

for dir in Commons Ui; do
  [[ -d $OMARCHY_PATH/shell/$dir ]] || { echo "Omaxian shell not found at $OMARCHY_PATH/shell/$dir" >&2; exit 1; }
done
command -v quickshell >/dev/null || { echo "quickshell is required" >&2; exit 1; }

rm -rf "$home"
mkdir -p "$home" "$bin" "$apps" "$data/icons/hicolor/scalable/apps"
cp "$here/shell.qml" "$here/set-wm-class.py" "$home/"
ln -s "$OMARCHY_PATH/shell/Commons" "$home/Commons"
ln -s "$OMARCHY_PATH/shell/Ui" "$home/Ui"
for item in ui manifest.json backend-version backend-api.json; do
  ln -s "$plugin/$item" "$home/$item"
done
# Plugin helpers, except the mailto ones, which need omarchy-shell.
mkdir "$home/scripts"
for file in "$plugin"/scripts/*; do
  ln -s "$file" "$home/scripts/$(basename "$file")"
done
for file in mailto.sh register-mailto.sh default-mail.sh; do
  ln -sf "$here/scripts/$file" "$home/scripts/$file"
done

install -m 755 "$here/omamail-app" "$bin/omamail-app"
install -m 644 "$here/omamail-app.desktop" "$apps/omamail-app.desktop"
install -m 644 "$plugin/ui/assets/omamail.svg" "$data/icons/hicolor/scalable/apps/omamail.svg"
update-desktop-database "$apps" >/dev/null 2>&1 || true

if (( build )); then
  command -v cargo >/dev/null || { echo "cargo is required for --build-backend" >&2; exit 1; }
  (cd "$plugin" && cargo build --locked --release)
  python3 "$plugin/scripts/backend-runtime.py" install-local
fi

if (( claim )); then
  xdg-mime default omamail-app.desktop x-scheme-handler/mailto
fi

echo "Installed. Run: omamail-app   (make sure $bin is on PATH)"
[[ -x $data/omamail/bin/omamail ]] || echo "Backend not installed: open Omamail and use its setup page, or re-run with --build-backend."
