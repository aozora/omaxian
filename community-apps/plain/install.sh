#!/bin/bash
# Omaxian / Debian install for Plain (Qt Quick config/text editor).
# Run from this directory, or: community-apps/plain/install.sh
#
#   ./install.sh
#   ./install.sh --skip-apt
#
# Upstream builds with CMake; bin/build falls back to plain.pro (qmake) when
# the Qt tree has no working cmake tools. There is no Arch makepkg script here.

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
  qml6-module-qtcore
  qml6-module-qtquick
  qml6-module-qtquick-controls
  qml6-module-qtquick-layouts
  qml6-module-qtquick-templates
  qml6-module-qtqml
  qml6-module-qtqml-workerscript
  qt6-qpa-plugins
  xdg-desktop-portal
  xdg-desktop-portal-gtk
)
apt_build=(
  build-essential
  cmake
  pkg-config
  qmake6
  qt6-base-dev
  qt6-declarative-dev
)

# apt's qt6-*-dev must match the Qt already on the system. A stock Excalibur
# box has 6.8 for both. A newer libqt6core with an older qt6-base-dev candidate
# would downgrade the desktop Qt.
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

# Qt headers/libs built for the Qt already on this machine, kept out of apt so
# the desktop libraries are not downgraded. Same layout Monologue/Signed use
# for qmake6: ~/.local/opt/omaxian-qt6-<major.minor>/usr
local_qt_prefix=""

find_local_qt_prefix() {
  local dir prefix
  shopt -s nullglob
  for dir in "$HOME"/.local/opt/omaxian-qt6-*/usr; do
    [[ -x $dir/bin/qmake6 || -f $dir/lib/x86_64-linux-gnu/cmake/Qt6/Qt6Config.cmake ]] || continue
    local_qt_prefix=$dir
  done
  shopt -u nullglob
  # Prefer an exact major.minor match to libqt6core when several exist.
  local installed inst_mm
  installed=$(dpkg-query -W -f '${Version}' libqt6core6t64 2>/dev/null || true)
  [[ -z $installed ]] && return 0
  inst_mm=${installed%%+*}
  inst_mm=${inst_mm%.*}
  prefix="$HOME/.local/opt/omaxian-qt6-${inst_mm}/usr"
  if [[ -x $prefix/bin/qmake6 || -f $prefix/lib/x86_64-linux-gnu/cmake/Qt6/Qt6Config.cmake ]]; then
    local_qt_prefix=$prefix
  fi
}

use_local_qt_if_present() {
  find_local_qt_prefix
  [[ -n $local_qt_prefix ]] || return 0
  if [[ -f $local_qt_prefix/lib/x86_64-linux-gnu/cmake/Qt6/Qt6Config.cmake ]]; then
    CMAKE_PREFIX_PATH="${local_qt_prefix}${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
    export CMAKE_PREFIX_PATH
  fi
  PATH="$local_qt_prefix/bin${PATH:+:$PATH}"
  export PATH
  echo ">> local Qt prefix $local_qt_prefix"
}

# Keep a package only when apt's candidate major.minor matches libqt6core
# (or there is no libqt6core yet). Avoids pulling Excalibur 6.8 QML onto a
# 6.10 desktop when freia's candidate is not selected.
qt_pkg_matches_installed() {
  local pkg=$1 installed candidate inst_mm cand_mm
  installed=$(dpkg-query -W -f '${Version}' libqt6core6t64 2>/dev/null || true)
  [[ -z $installed ]] && return 0
  candidate=$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/{print $2; exit}')
  [[ -z $candidate || $candidate == "(none)" ]] && return 1
  inst_mm=${installed%%+*}
  inst_mm=${inst_mm%.*}
  cand_mm=${candidate%%+*}
  cand_mm=${cand_mm%.*}
  [[ $inst_mm == "$cand_mm" ]]
}

install_apt() {
  (( SKIP_APT )) && return 0
  if ! command -v apt-get >/dev/null; then
    echo "apt-get not found; install deps yourself (see omaxian.deps.json)" >&2
    return 0
  fi
  local packages=() pkg
  if [[ -n $local_qt_prefix ]]; then
    # Build against the local tree; still pull matching *runtime* QML modules
    # from apt when their candidate matches libqt6core. Skip -dev / qmake.
    for pkg in "${apt_runtime[@]}"; do
      case "$pkg" in
        qt6-qpa-plugins|xdg-desktop-portal*)
          packages+=("$pkg")
          ;;
        qml6-*)
          if qt_pkg_matches_installed "$pkg"; then
            packages+=("$pkg")
          else
            echo ">> skip $pkg (apt candidate does not match libqt6core)"
          fi
          ;;
        *)
          packages+=("$pkg")
          ;;
      esac
    done
    for pkg in "${apt_build[@]}"; do
      case "$pkg" in
        qmake6|qt6-*|libqt6*|qml6-*) ;;
        *) packages+=("$pkg") ;;
      esac
    done
    echo ">> matching Qt headers under $local_qt_prefix; skipping apt Qt -dev packages"
  else
    refuse_qt_downgrade
    packages=("${apt_runtime[@]}" "${apt_build[@]}")
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
    local qmake_bin=""
    [[ -x $local_qt_prefix/bin/qmake6 ]] && qmake_bin=$local_qt_prefix/bin/qmake6
    if [[ -n $qmake_bin ]]; then
      echo ">> qmake6 $($qmake_bin -query QT_VERSION) ($qmake_bin); libqt6core $qt_lib"
      return 0
    fi
    echo ">> local Qt $local_qt_prefix (libqt6core $qt_lib); cmake will probe"
    return 0
  fi
  if [[ -f /usr/lib/x86_64-linux-gnu/cmake/Qt6/Qt6Config.cmake ]]; then
    echo ">> cmake $(cmake --version | head -1 | awk '{print $3}'); system Qt $qt_lib"
    return 0
  fi
  if command -v qmake6 >/dev/null; then
    echo ">> qmake6 $(qmake6 -query QT_VERSION); libqt6core $qt_lib"
    return 0
  fi
  echo "No Qt6 build tools found. Install qt6-base-dev + qt6-declarative-dev, or a matching ~/.local/opt/omaxian-qt6-<mm>/." >&2
  exit 1
}

# Main.qml imports QtCore (StandardPaths / StandardKey). Stock Excalibur ships
# that as qml6-module-qtcore. When apt cannot match libqt6core, the module may
# live under ~/.local/lib/qt6/qml (same pattern as Monologue's Multimedia).
needs_qml_wrapper() {
  [[ ! -d /usr/lib/x86_64-linux-gnu/qt6/qml/QtCore ]] || return 1
  [[ -d $HOME/.local/lib/qt6/qml/QtCore ]]
}

install_files() {
  mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_DIR"
  if needs_qml_wrapper; then
    mkdir -p "$PREFIX/libexec"
    install -m 0755 "$ROOT/build/plain" "$PREFIX/libexec/plain"
    local lib_extra="$HOME/.local/lib"
    local qml_extra="$lib_extra/qt6/qml"
    cat > "$BIN_DIR/plain" <<EOF
#!/bin/bash
export LD_LIBRARY_PATH="\${LD_LIBRARY_PATH:+\$LD_LIBRARY_PATH:}$lib_extra"
export QML_IMPORT_PATH="\${QML_IMPORT_PATH:+\$QML_IMPORT_PATH:}$qml_extra"
exec "$PREFIX/libexec/plain" "\$@"
EOF
    chmod 0755 "$BIN_DIR/plain"
    echo ">> wrapper $BIN_DIR/plain (QML from $qml_extra)"
  else
    install -m 0755 "$ROOT/build/plain" "$BIN_DIR/plain"
    if [[ ! -d /usr/lib/x86_64-linux-gnu/qt6/qml/QtCore ]]; then
      echo "warning: qml6-module-qtcore is not installed; Plain will exit on start" >&2
      echo "  install a package matching libqt6core, or place QtCore under ~/.local/lib/qt6/qml/" >&2
    fi
  fi
  install -m 0644 "$ROOT/pkgbuild/plain.svg" "$ICON_DIR/plain.svg"
  sed -e "s|^Exec=plain|Exec=$BIN_DIR/plain|" \
    "$ROOT/pkgbuild/plain.desktop" > "$APP_DIR/plain.desktop"
  chmod 0644 "$APP_DIR/plain.desktop"
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
  binary   $BIN_DIR/plain
  desktop  $APP_DIR/plain.desktop
  icon     $ICON_DIR/plain.svg

Open Plain from the launcher, or:
  $BIN_DIR/plain ~/.config/i3/config
  EDITOR=$BIN_DIR/plain git commit

EOF
