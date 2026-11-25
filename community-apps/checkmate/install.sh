#!/bin/bash
# Omaxian / Debian install for Checkmate (3D chess).
# Run from this directory, or: community-apps/checkmate/install.sh
#
#   ./install.sh                 # pinned pre-built binary when available
#   ./install.sh --from-source   # always compile
#   ./install.sh --skip-apt
#
# Upstream builds with CMake (bin/build); the version comes from
# .omaxian-upstream-version. Arch pacman helpers in bin/build are skipped on
# Debian — this script installs deps via apt.
#
# Quick 3D must match the desktop Qt private ABI. When the local
# ~/.local/opt/omaxian-qt6-<mm>/ overlay (or apt) has no matching Quick3D,
# install.sh builds in a debian:trixie container and ships a private Qt 6.8
# runtime next to the binary (same idea as CI's 6.8 prebuilts).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
LIBEXEC_DIR="$PREFIX/libexec"
APP_DIR="$PREFIX/share/applications"
ICON_DIR="$PREFIX/share/icons/hicolor/scalable/apps"
QT_RUNTIME_DIR="$PREFIX/lib/checkmate-qt"
NAME="checkmate"

SKIP_APT=0
FROM_SOURCE=0
# Set when the binary needs the private Qt tree under QT_RUNTIME_DIR.
USE_PRIVATE_QT=0

usage() {
  cat <<'EOF'
Usage: install.sh [--from-source] [--skip-apt]

  (default)      pinned pre-built binary (runtime apt only) → ~/.local;
                 falls back to native cmake, then a container build with a
                 private Qt 6.8 runtime when Quick3D is not on this machine
  --from-source  never download a pinned binary
  --skip-apt     do not apt-get install deps
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

# Package lists live in omaxian.deps.json (the TUI reads the same file).
# shellcheck source=../lib/prebuilt.sh
source "$ROOT/../lib/prebuilt.sh"
app_deps_read

refuse_qt_downgrade() {
  local installed candidate inst_mm cand_mm
  installed=$(dpkg-query -W -f '${Version}' libqt6core6t64 2>/dev/null || true)
  [[ -z $installed ]] && return 0
  candidate=$(apt-cache policy qt6-base-dev 2>/dev/null | awk '/Candidate:/ && !seen {print $2; seen=1}')
  [[ -z $candidate || $candidate == "(none)" ]] && return 0
  inst_mm=${installed%%+*}
  inst_mm=${inst_mm%.*}
  cand_mm=${candidate%%+*}
  cand_mm=${cand_mm%.*}
  if [[ $inst_mm != "$cand_mm" ]]; then
    echo "Installed Qt is $installed but apt's qt6-base-dev candidate is $candidate." >&2
    echo "Refusing to apt-install Qt packages: that would mix or downgrade the desktop Qt." >&2
    return 1
  fi
  return 0
}

local_qt_prefix=""

# Local overlay must include Quick3D — a headers-only 6.10 tree without it
# makes cmake look there and fail, while skipping apt Qt packages.
find_local_qt_prefix() {
  local dir prefix
  local_qt_prefix=""
  shopt -s nullglob
  for dir in "$HOME"/.local/opt/omaxian-qt6-*/usr; do
    [[ -f $dir/lib/x86_64-linux-gnu/cmake/Qt6/Qt6Config.cmake ]] || continue
    [[ -f $dir/lib/x86_64-linux-gnu/cmake/Qt6Quick3D/Qt6Quick3DConfig.cmake ]] || continue
    local_qt_prefix=$dir
  done
  shopt -u nullglob
  local installed inst_mm
  installed=$(dpkg-query -W -f '${Version}' libqt6core6t64 2>/dev/null || true)
  [[ -z $installed ]] && return 0
  inst_mm=${installed%%+*}
  inst_mm=${inst_mm%.*}
  prefix="$HOME/.local/opt/omaxian-qt6-${inst_mm}/usr"
  if [[ -f $prefix/lib/x86_64-linux-gnu/cmake/Qt6Quick3D/Qt6Quick3DConfig.cmake ]]; then
    local_qt_prefix=$prefix
  fi
}

use_local_qt_if_present() {
  find_local_qt_prefix
  if [[ -z $local_qt_prefix ]]; then
    local incomplete=""
    shopt -s nullglob
    for dir in "$HOME"/.local/opt/omaxian-qt6-*/usr; do
      [[ -f $dir/lib/x86_64-linux-gnu/cmake/Qt6/Qt6Config.cmake ]] || continue
      if [[ ! -f $dir/lib/x86_64-linux-gnu/cmake/Qt6Quick3D/Qt6Quick3DConfig.cmake ]]; then
        incomplete=$dir
      fi
    done
    shopt -u nullglob
    if [[ -n $incomplete ]]; then
      echo ">> local Qt $incomplete has no Quick3D; not using it for Checkmate"
    fi
    return 0
  fi
  CMAKE_PREFIX_PATH="${local_qt_prefix}${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
  export CMAKE_PREFIX_PATH
  PATH="$local_qt_prefix/bin${PATH:+:$PATH}"
  export PATH
  echo ">> local Qt prefix $local_qt_prefix (with Quick3D)"
}

install_apt() {
  (( SKIP_APT )) && return 0
  if ! command -v apt-get >/dev/null; then
    echo "apt-get not found; install deps yourself (see omaxian.deps.json)" >&2
    return 0
  fi
  local packages=() pkg
  if (( USE_PRIVATE_QT )); then
    # Private Qt tree supplies Qt/QML; only non-Qt runtime (GL, icons, portal).
    for pkg in "${apt_runtime[@]}"; do
      case "$pkg" in
        qt6-*|libqt6*|qml6-*) ;;
        *) packages+=("$pkg") ;;
      esac
    done
  elif [[ -n $local_qt_prefix ]]; then
    for pkg in "${apt_runtime[@]}" "${apt_build[@]}"; do
      case "$pkg" in
        qt6-*|libqt6*|qml6-*) ;;
        *) packages+=("$pkg") ;;
      esac
    done
    echo ">> matching Qt headers under $local_qt_prefix; skipping apt Qt packages"
  else
    if (( ${#apt_build[@]} > 0 )) && ! refuse_qt_downgrade; then
      return 1
    fi
    packages=("${apt_runtime[@]}" "${apt_build[@]}")
  fi
  if (( ${#packages[@]} == 0 )); then
    return 0
  fi
  echo ">> apt packages: ${packages[*]}"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
}

container_engine() {
  local e
  for e in podman docker; do
    if command -v "$e" >/dev/null; then
      printf '%s\n' "$e"
      return 0
    fi
  done
  return 1
}

# True when we can cmake+build on this host (local overlay with Quick3D, or
# system Qt headers that apt can match without downgrading).
native_build_possible() {
  if [[ -n $local_qt_prefix ]]; then
    return 0
  fi
  if [[ -f /usr/lib/x86_64-linux-gnu/cmake/Qt6Quick3D/Qt6Quick3DConfig.cmake ]] \
    && refuse_qt_downgrade; then
    return 0
  fi
  return 1
}

# Build in debian:trixie and stage binary + private Qt 6.8 runtime under build/.
build_in_container() {
  local engine image stage
  engine=$(container_engine) || {
    echo "Quick3D is not available for a native build, and neither podman nor docker is installed." >&2
    echo "Install podman (or docker), or add Qt Quick 3D to ~/.local/opt/omaxian-qt6-<mm>/usr, then re-run." >&2
    exit 1
  }
  image=docker.io/library/debian:trixie
  stage="$ROOT/build/qt-runtime"
  echo ">> building $NAME in $engine ($image) with a private Qt 6.8 runtime"
  rm -rf "$ROOT/build"
  mkdir -p "$ROOT/build"
  "$engine" run --rm \
    -v "$ROOT:/src:Z" \
    -w /src \
    "$image" \
    bash -c '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  build-essential cmake pkg-config \
  qt6-base-dev qt6-declarative-dev qt6-quick3d-dev \
  libgl1 libgl1-mesa-dri mesa-libgallium \
  qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts \
  qml6-module-qtquick-templates qml6-module-qtquick-shapes \
  qml6-module-qtqml qml6-module-qtqml-workerscript qml6-module-qtquick3d \
  libqt6quick3d6 libqt6concurrent6 libqt6network6 libqt6shadertools6 \
  qt6-qpa-plugins qt6-svg-plugins qt6-image-formats-plugins \
  >/dev/null
bin/build
mkdir -p build/qt-runtime/{lib,qml,plugins}
install -m 0755 build/checkmate build/qt-runtime/checkmate
cp -a /usr/lib/x86_64-linux-gnu/libQt6*.so* build/qt-runtime/lib/
for m in QtQuick QtQml QtCore Qt QtNetwork QtQuick3D; do
  [[ -d /usr/lib/x86_64-linux-gnu/qt6/qml/$m ]] && cp -a "/usr/lib/x86_64-linux-gnu/qt6/qml/$m" build/qt-runtime/qml/
done
cp -a /usr/lib/x86_64-linux-gnu/qt6/plugins/platforms build/qt-runtime/plugins/
cp -a /usr/lib/x86_64-linux-gnu/qt6/plugins/xcbglintegrations build/qt-runtime/plugins/
cp -a /usr/lib/x86_64-linux-gnu/qt6/plugins/imageformats build/qt-runtime/plugins/ 2>/dev/null || true
cp -a /usr/lib/x86_64-linux-gnu/qt6/plugins/iconengines build/qt-runtime/plugins/ 2>/dev/null || true
'
  [[ -x $ROOT/build/qt-runtime/checkmate ]] || {
    echo "container build did not produce build/qt-runtime/checkmate" >&2
    exit 1
  }
  USE_PRIVATE_QT=1
  BUILT_BIN="$ROOT/build/qt-runtime/checkmate"
  echo ">> private Qt runtime staged ($(du -sh "$stage" | awk "{print \$1}"))"
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
  if [[ -f /usr/lib/x86_64-linux-gnu/cmake/Qt6Quick3D/Qt6Quick3DConfig.cmake ]]; then
    echo ">> cmake $(cmake --version | head -1 | awk '{print $3}'); system Qt $qt_lib"
    return 0
  fi
  echo "No Qt6 Quick3D cmake config found." >&2
  exit 1
}

install_files() {
  mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_DIR"
  if (( USE_PRIVATE_QT )); then
    mkdir -p "$LIBEXEC_DIR" "$QT_RUNTIME_DIR"
    rm -rf "$QT_RUNTIME_DIR"
    mkdir -p "$QT_RUNTIME_DIR"
    cp -a "$ROOT/build/qt-runtime/lib" "$QT_RUNTIME_DIR/"
    cp -a "$ROOT/build/qt-runtime/qml" "$QT_RUNTIME_DIR/"
    cp -a "$ROOT/build/qt-runtime/plugins" "$QT_RUNTIME_DIR/"
    install -m 0755 "$BUILT_BIN" "$LIBEXEC_DIR/$NAME"
    cat > "$BIN_DIR/$NAME" <<EOF
#!/bin/bash
export LD_LIBRARY_PATH="$QT_RUNTIME_DIR/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export QML_IMPORT_PATH="$QT_RUNTIME_DIR/qml\${QML_IMPORT_PATH:+:\$QML_IMPORT_PATH}"
export QT_PLUGIN_PATH="$QT_RUNTIME_DIR/plugins\${QT_PLUGIN_PATH:+:\$QT_PLUGIN_PATH}"
exec "$LIBEXEC_DIR/$NAME" "\$@"
EOF
    chmod 0755 "$BIN_DIR/$NAME"
    echo ">> wrapper $BIN_DIR/$NAME (private Qt under $QT_RUNTIME_DIR)"
  else
    install -m 0755 "$BUILT_BIN" "$BIN_DIR/$NAME"
  fi
  install -m 0644 "$ROOT/share/$NAME.svg" "$ICON_DIR/$NAME.svg"
  sed -e "s|^Exec=$NAME open|Exec=$BIN_DIR/$NAME open|" \
    "$ROOT/share/$NAME.desktop" > "$APP_DIR/$NAME.desktop"
  chmod 0644 "$APP_DIR/$NAME.desktop"
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
BUILT_BIN="$ROOT/build/$NAME"
if prebuilt_fetch "$NAME"; then
  apt_build=()
  install_apt
  BUILT_BIN=$PREBUILT_BIN
elif native_build_possible; then
  install_apt
  qt_build_ready
  echo ">> bin/build"
  "$ROOT/bin/build"
else
  echo ">> native Quick3D build not available on this Qt; using container"
  apt_build=()
  USE_PRIVATE_QT=1
  install_apt
  build_in_container
fi
install_files

cat <<EOF

Installed:
  binary   $BIN_DIR/$NAME
  desktop  $APP_DIR/$NAME.desktop
  icon     $ICON_DIR/$NAME.svg
EOF
if (( USE_PRIVATE_QT )); then
  cat <<EOF
  runtime  $QT_RUNTIME_DIR (private Qt 6.8; desktop Qt has no matching Quick3D)
EOF
fi
cat <<EOF

Open Checkmate from the launcher, or:
  $BIN_DIR/checkmate open

Headless: $BIN_DIR/checkmate inspect | export | legal [FEN]

EOF
