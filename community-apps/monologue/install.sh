#!/bin/bash
# Omaxian / Debian install for Monologue (Qt Quick webcam recorder).
# Run from this directory, or: community-apps/monologue/install.sh
#
#   ./install.sh
#   ./install.sh --skip-apt
#
# Arch packaging remains in bin/install.arch (makepkg). Do not use it here.

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

  (default)  apt deps, qmake6 build, install to ~/.local
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
  ffmpeg
  libpulse0
  libqt6multimedia6
  qml6-module-qtmultimedia
  qml6-module-qtquick
  qml6-module-qtquick-controls
  qml6-module-qtquick-layouts
  qml6-module-qtquick-shapes
  qt6-qpa-plugins
  xdg-desktop-portal
  xdg-desktop-portal-gtk
)
apt_build=(
  build-essential
  pkg-config
  qmake6
  qt6-base-dev
  qt6-declarative-dev
  qt6-multimedia-dev
  libpulse-dev
)

# apt's qmake6 must match the Qt already on the system. A stock Excalibur
# box has 6.8 for both. A newer libqt6core with an older qmake6 candidate
# would downgrade the desktop Qt.
refuse_qt_downgrade() {
  local installed candidate inst_mm cand_mm
  installed=$(dpkg-query -W -f '${Version}' libqt6core6t64 2>/dev/null || true)
  [[ -z $installed ]] && return 0
  candidate=$(apt-cache policy qmake6 2>/dev/null | awk '/Candidate:/{print $2; exit}')
  [[ -z $candidate || $candidate == "(none)" ]] && return 0
  inst_mm=${installed%%+*}
  inst_mm=${inst_mm%.*}
  cand_mm=${candidate%%+*}
  cand_mm=${cand_mm%.*}
  if [[ $inst_mm != "$cand_mm" ]]; then
    echo "Installed Qt is $installed but apt's qmake6 candidate is $candidate." >&2
    echo "Refusing to apt-install Qt packages: that would mix or downgrade the desktop Qt." >&2
    echo "Install a matching qmake6 yourself and re-run with --skip-apt." >&2
    exit 1
  fi
}

# A qmake built for the Qt already on this machine, kept out of apt so the
# desktop libraries are not downgraded. Created by hand when apt's qmake6
# candidate is a different major.minor than libqt6core.
local_qmake="$HOME/.local/opt/omaxian-qt6-6.10/usr/bin/qmake6"

use_local_qmake_if_present() {
  [[ -x $local_qmake ]] || return 0
  PATH="$(dirname "$local_qmake"):$PATH"
  export PATH
}

install_apt() {
  (( SKIP_APT )) && return 0
  if ! command -v apt-get >/dev/null; then
    echo "apt-get not found; install deps yourself (see omaxian.deps.json)" >&2
    return 0
  fi
  local packages=("${apt_runtime[@]}" "${apt_build[@]}")
  if [[ -x $local_qmake ]]; then
    local kept=() pkg
    for pkg in "${packages[@]}"; do
      case "$pkg" in
        qmake6|qt6-*|libqt6*|qml6-*) ;;
        *) kept+=("$pkg") ;;
      esac
    done
    packages=("${kept[@]}")
    echo ">> matching qmake6 is $local_qmake; skipping apt Qt packages"
  else
    refuse_qt_downgrade
  fi
  if (( ${#packages[@]} == 0 )); then
    return 0
  fi
  echo ">> apt packages: ${packages[*]}"
  sudo apt-get install -y --no-install-recommends "${packages[@]}"
}

qt_versions_match() {
  local qmake_bin qt_qmake qt_lib qmake_mm lib_mm
  qmake_bin=$(command -v qmake6 || true)
  if [[ -z $qmake_bin ]]; then
    echo "qmake6 not found" >&2
    exit 1
  fi
  qt_qmake=$("$qmake_bin" -query QT_VERSION)
  qt_lib=$(dpkg-query -W -f '${Version}' libqt6core6t64 2>/dev/null || true)
  qmake_mm=${qt_qmake%.*}
  lib_mm=${qt_lib%%+*}
  lib_mm=${lib_mm%-*}
  # 6.8.2+dfsg-9 → 6.8.2, then drop the patch level for the comparison below.
  lib_mm=${lib_mm%.*}
  if [[ -n $qt_lib && $qmake_mm != "$lib_mm" ]]; then
    echo "qmake6 is Qt $qt_qmake but libqt6core6t64 is $qt_lib." >&2
    echo "Refusing to build: apt would mix Qt ABIs. Install a qmake6 that matches the installed Qt, and do not downgrade libqt6core." >&2
    exit 1
  fi
  echo ">> Qt $qt_qmake ($qmake_bin)"
}

install_files() {
  mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_DIR"
  local qml_extra="$HOME/.local/lib/qt6/qml"
  if [[ -d $qml_extra/QtMultimedia && ! -d /usr/lib/x86_64-linux-gnu/qt6/qml/QtMultimedia ]]; then
    mkdir -p "$PREFIX/libexec"
    install -m 0755 "$ROOT/build/monologue" "$PREFIX/libexec/monologue"
    cat > "$BIN_DIR/monologue" <<EOF
#!/bin/bash
export QML_IMPORT_PATH="\${QML_IMPORT_PATH:+\$QML_IMPORT_PATH:}$qml_extra"
exec "$PREFIX/libexec/monologue" "\$@"
EOF
    chmod 0755 "$BIN_DIR/monologue"
  else
    install -m 0755 "$ROOT/build/monologue" "$BIN_DIR/monologue"
  fi
  install -m 0644 "$ROOT/pkgbuild/monologue.svg" "$ICON_DIR/monologue.svg"
  sed -e "s|^Exec=monologue|Exec=$BIN_DIR/monologue|" \
    "$ROOT/pkgbuild/monologue.desktop" > "$APP_DIR/monologue.desktop"
  chmod 0644 "$APP_DIR/monologue.desktop"
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

use_local_qmake_if_present
install_apt
qt_versions_match
echo ">> bin/build"
"$ROOT/bin/build"
install_files

cat <<EOF

Installed:
  binary   $BIN_DIR/monologue
  desktop  $APP_DIR/monologue.desktop
  icon     $ICON_DIR/monologue.svg

Open Monologue from the launcher, or:
  $BIN_DIR/monologue

EOF
