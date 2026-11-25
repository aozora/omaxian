#!/bin/bash
# Omaxian / Debian install for Aether (Wails theming app).
# Run from this directory, or: community-apps/aether/install.sh
#
#   ./install.sh                 # pinned Omaxian CI binary (x86_64)
#   ./install.sh --from-source   # apt build deps + bin/build
#   ./install.sh --skip-apt
#
# The default downloads the binary pinned in .omaxian-prebuilt and checks its
# sha256; it builds when there is no usable binary. Replaces upstream's AUR
# installer.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"

SKIP_APT=0
FROM_SOURCE=0

usage() {
  cat <<'EOF'
Usage: install.sh [--from-source] [--skip-apt]

  (default)      pinned binary → ~/.local; builds when none is usable
  --from-source  apt build deps, bin/build, install to ~/.local
  --skip-apt     do not apt-get install deps
  Also makes Aether the handler for aether:// links.
EOF
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --skip-apt) SKIP_APT=1 ;;
    --from-source) FROM_SOURCE=1 ;;
    -h|--help) usage ;;
    *)
      echo "unknown option: $arg" >&2
      usage
      ;;
  esac
done

if (( $(id -u) == 0 )); then
  echo "refuse to install as root — run as your login user" >&2
  exit 1
fi

# shellcheck source=../lib/prebuilt.sh
source "$ROOT/../lib/prebuilt.sh"
app_deps_read

# install_apt [--build] — runtime packages, plus build packages with --build.
install_apt() {
  (( SKIP_APT )) && return 0
  if ! command -v apt-get >/dev/null; then
    echo "apt-get not found; install deps yourself (see omaxian.deps.json)" >&2
    return 0
  fi
  local packages=("${apt_runtime[@]}")
  if [[ ${1:-} == "--build" ]]; then
    packages+=("${apt_build[@]}")
  fi
  echo ">> apt packages: ${packages[*]}"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
}

# install_files <binary> — the binary, launcher entries and icon, as
# upstream's `make install` lays them out, under $PREFIX.
install_files() {
  local bin="$1" bindir="$PREFIX/bin" appdir="$PREFIX/share/applications"
  local icondir="$PREFIX/share/icons/hicolor/512x512/apps" desktop
  echo ">> install aether → $PREFIX"
  install -d "$bindir" "$appdir" "$icondir"
  install -m 0755 "$bin" "$bindir/aether"
  install -m 0644 "$ROOT/assets/aether-icon-512.png" "$icondir/aether.png"
  # Absolute Exec: launchers started outside the X session may lack ~/.local/bin.
  for desktop in li.oever.aether.desktop li.oever.aether.url-handler.desktop; do
    sed "s|^Exec=aether|Exec=$bindir/aether|" "$ROOT/$desktop" > "$appdir/$desktop"
    chmod 0644 "$appdir/$desktop"
  done
  if command -v update-desktop-database >/dev/null; then
    update-desktop-database "$appdir" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null; then
    gtk-update-icon-cache -q -t -f "$PREFIX/share/icons/hicolor" >/dev/null 2>&1 || true
  fi
  if command -v xdg-mime >/dev/null; then
    xdg-mime default li.oever.aether.url-handler.desktop x-scheme-handler/aether || true
  fi
}

if prebuilt_fetch aether; then
  install_apt
  install_files "$PREBUILT_BIN"
else
  install_apt --build
  "$ROOT/bin/build"
  install_files "$ROOT/build/aether"
fi

cat <<EOF

Installed:
  binary   $PREFIX/bin/aether
  desktop  $PREFIX/share/applications/li.oever.aether.desktop
  icon     $PREFIX/share/icons/hicolor/512x512/apps/aether.png

Open Aether from the launcher, or:
  $PREFIX/bin/aether
  $PREFIX/bin/aether --help    # headless CLI

EOF
