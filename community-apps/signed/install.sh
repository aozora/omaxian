#!/bin/bash
# Omaxian / Debian install for Signed (Qt Quick PDF signer).
# Run from this directory, or: community-apps/signed/install.sh
#
#   ./install.sh
#   ./install.sh --skip-apt
#
# Upstream builds with CMake. Arch packaging remains in bin/install.arch.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
APP_DIR="$PREFIX/share/applications"
ICON_DIR="$PREFIX/share/icons/hicolor/scalable/apps"

SKIP_APT=0

usage() {
  cat <<'EOF'
Usage: install.sh [--skip-apt]

  (default)  apt deps, cmake build, install to ~/.local
  --skip-apt do not apt-get install deps
EOF
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --skip-apt) SKIP_APT=1 ;;
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

apt_runtime=(
  libpoppler-qt6-3t64
  libqpdf30
  libnss3
  fonts-noto-core
  qml6-module-qtquick
  qml6-module-qtquick-controls
  qml6-module-qtquick-layouts
  qml6-module-qtquick-shapes
  qt6-qpa-plugins
  qt6-image-formats-plugins
  xdg-desktop-portal
  xdg-desktop-portal-gtk
)
apt_build=(
  build-essential
  cmake
  pkg-config
  qt6-base-dev
  qt6-declarative-dev
  libpoppler-qt6-dev
  libqpdf-dev
)

refuse_qt_downgrade() {
  local installed candidate inst_mm cand_mm
  installed=$(dpkg-query -W -f '${Version}' libqt6core6t64 2>/dev/null || true)
  [[ -z $installed ]] && return 0
  candidate=$(apt-cache policy qt6-base-dev 2>/dev/null | awk '/Candidate:/{print $2; exit}')
  [[ -z $candidate || $candidate == "(none)" ]] && return 0
  inst_mm=${installed%%+*}
  inst_mm=${inst_mm%.*}
  cand_mm=${candidate%%+*}
  cand_mm=${cand_mm%.*}
  if [[ $inst_mm != "$cand_mm" ]]; then
    echo "Installed Qt is $installed but apt's qt6-base-dev candidate is $candidate." >&2
    echo "Refusing to apt-install Qt packages: that would mix or downgrade the desktop Qt." >&2
    echo "Install matching Qt headers yourself (or use ~/.local/opt/omaxian-qt6-<mm>/) and re-run with --skip-apt." >&2
    exit 1
  fi
}

local_qt_prefix=""

find_local_qt_prefix() {
  local dir prefix
  shopt -s nullglob
  for dir in "$HOME"/.local/opt/omaxian-qt6-*/usr; do
    [[ -f $dir/lib/x86_64-linux-gnu/cmake/Qt6/Qt6Config.cmake ]] || continue
    local_qt_prefix=$dir
  done
  shopt -u nullglob
  local installed inst_mm
  installed=$(dpkg-query -W -f '${Version}' libqt6core6t64 2>/dev/null || true)
  [[ -z $installed ]] && return 0
  inst_mm=${installed%%+*}
  inst_mm=${inst_mm%.*}
  prefix="$HOME/.local/opt/omaxian-qt6-${inst_mm}/usr"
  if [[ -f $prefix/lib/x86_64-linux-gnu/cmake/Qt6/Qt6Config.cmake ]]; then
    local_qt_prefix=$prefix
  fi
}

use_local_qt_if_present() {
  find_local_qt_prefix
  [[ -n $local_qt_prefix ]] || return 0
  CMAKE_PREFIX_PATH="${local_qt_prefix}${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
  export CMAKE_PREFIX_PATH
  PATH="$local_qt_prefix/bin${PATH:+:$PATH}"
  export PATH
  local pc_dir="${local_qt_prefix%/usr}/pkgconfig"
  if [[ -d $pc_dir ]]; then
    PKG_CONFIG_PATH="$pc_dir${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    export PKG_CONFIG_PATH
  fi
  echo ">> local Qt prefix $local_qt_prefix"
}

install_apt() {
  (( SKIP_APT )) && return 0
  if ! command -v apt-get >/dev/null; then
    echo "apt-get not found; install deps yourself (see omaxian.deps.json)" >&2
    return 0
  fi
  local packages=("${apt_runtime[@]}" "${apt_build[@]}")
  if [[ -n $local_qt_prefix ]]; then
    local kept=() pkg
    for pkg in "${packages[@]}"; do
      case "$pkg" in
        qt6-*|libqt6*|qml6-*|libpoppler-qt6-dev|libqpdf-dev) ;;
        *) kept+=("$pkg") ;;
      esac
    done
    packages=("${kept[@]}")
    echo ">> matching Qt headers under $local_qt_prefix; skipping apt Qt and poppler-dev packages"
  else
    refuse_qt_downgrade
  fi
  if (( ${#packages[@]} == 0 )); then
    return 0
  fi
  echo ">> apt packages: ${packages[*]}"
  sudo apt-get install -y --no-install-recommends "${packages[@]}"
}

qt_build_ready() {
  local qt_lib
  qt_lib=$(dpkg-query -W -f '${Version}' libqt6core6t64 2>/dev/null || true)
  if [[ -n $local_qt_prefix ]]; then
    echo ">> local Qt $local_qt_prefix (libqt6core $qt_lib); cmake will probe"
    return 0
  fi
  if ! command -v cmake >/dev/null; then
    echo "cmake not found" >&2
    exit 1
  fi
  if [[ -f /usr/lib/x86_64-linux-gnu/cmake/Qt6/Qt6Config.cmake ]]; then
    echo ">> cmake $(cmake --version | head -1 | awk '{print $3}'); system Qt $qt_lib"
    return 0
  fi
  echo "No Qt6 cmake config found. Install qt6-base-dev + qt6-declarative-dev, or a matching ~/.local/opt/omaxian-qt6-<mm>/." >&2
  exit 1
}

install_files() {
  mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_DIR"
  install -m 0755 "$ROOT/build/signed" "$BIN_DIR/signed"
  install -m 0644 "$ROOT/pkgbuild/signed.svg" "$ICON_DIR/signed.svg"
  sed -e "s|^Exec=signed open %f|Exec=$BIN_DIR/signed open %f|" \
    "$ROOT/pkgbuild/signed.desktop" > "$APP_DIR/signed.desktop"
  chmod 0644 "$APP_DIR/signed.desktop"
  if command -v update-desktop-database >/dev/null; then
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null; then
    gtk-update-icon-cache -q -t -f "$PREFIX/share/icons/hicolor" >/dev/null 2>&1 || true
  fi
  if [[ :$PATH: != *":$BIN_DIR:"* ]]; then
    echo "note: $BIN_DIR is not on PATH; the desktop entry uses the full path"
  fi
}

use_local_qt_if_present
install_apt
qt_build_ready
echo ">> bin/build"
"$ROOT/bin/build"
install_files

cat <<EOF

Installed:
  binary   $BIN_DIR/signed
  desktop  $APP_DIR/signed.desktop
  icon     $ICON_DIR/signed.svg

Open Signed from the launcher, or:
  $BIN_DIR/signed open /path/to/file.pdf

Registered for PDFs. It does not replace the default PDF viewer.

EOF