#!/bin/bash
# Omaxian / Debian install for Flowtunes (endless local music).
# Run from this directory, or: community-apps/flowtunes/install.sh
#
#   ./install.sh                 # pinned pre-built binary when available
#   ./install.sh --from-source   # always compile
#   ./install.sh --skip-apt
#
# Upstream builds with CMake (bin/build); needs Qt Multimedia and Qt ShaderTools.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
APP_DIR="$PREFIX/share/applications"
ICON_DIR="$PREFIX/share/icons/hicolor/scalable/apps"
NAME="flowtunes"

SKIP_APT=0
FROM_SOURCE=0

usage() {
  cat <<'EOF'
Usage: install.sh [--from-source] [--skip-apt]

  (default)      pinned pre-built binary (runtime apt only) → ~/.local;
                 falls back to apt build deps + cmake build
  --from-source  always apt build deps + cmake build
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
  echo ">> local Qt prefix $local_qt_prefix"
}

install_apt() {
  (( SKIP_APT )) && return 0
  if ! command -v apt-get >/dev/null; then
    echo "apt-get not found; install deps yourself (see omaxian.deps.json)" >&2
    return 0
  fi
  local packages=() pkg
  if [[ -n $local_qt_prefix ]]; then
    for pkg in "${apt_runtime[@]}" "${apt_build[@]}"; do
      case "$pkg" in
        qt6-*|libqt6*|qml6-*) ;;
        *) packages+=("$pkg") ;;
      esac
    done
    echo ">> matching Qt headers under $local_qt_prefix; skipping apt Qt packages"
  else
    (( ${#apt_build[@]} == 0 )) || refuse_qt_downgrade
    packages=("${apt_runtime[@]}" "${apt_build[@]}")
  fi
  if (( ${#packages[@]} == 0 )); then
    return 0
  fi
  echo ">> apt packages: ${packages[*]}"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
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

# QtMultimedia is imported from QML. When the system has none (apt only has
# Qt 6.8 while the desktop runs 6.10) but ~/.local/lib/qt6/qml does, run the
# app through a wrapper that points at it, as Folio does.
needs_qml_wrapper() {
  local sys=/usr/lib/x86_64-linux-gnu/qt6/qml
  local local_qml=$HOME/.local/lib/qt6/qml
  [[ -d $local_qml/QtMultimedia && ! -d $sys/QtMultimedia ]]
}

# The aurora shader is compiled by Qt ShaderTools at build time. A local Qt
# overlay (~/.local/opt/omaxian-qt6-<mm>) often has headers but no ShaderTools,
# and apt only offers Qt 6.8. A binary built against Qt 6.8 runs on 6.8 and
# newer, so build it in a Debian trixie container instead.
host_can_build() {
  [[ -z $local_qt_prefix ]] && return 0
  [[ -f $local_qt_prefix/lib/x86_64-linux-gnu/cmake/Qt6ShaderTools/Qt6ShaderToolsConfig.cmake ]]
}

build_in_container() {
  local engine=""
  for e in podman docker; do
    if command -v "$e" >/dev/null; then engine=$e; break; fi
  done
  if [[ -z $engine ]]; then
    echo "The local Qt has no ShaderTools, and neither podman nor docker is available to build in." >&2
    echo "Install qt6-shadertools-dev matching your Qt, or install podman." >&2
    exit 1
  fi
  echo ">> building against Qt 6.8 in a debian:trixie container ($engine)"
  rm -rf "$ROOT/build"
  mkdir -p "$ROOT/build"
  "$engine" run --rm -v "$ROOT:/src:ro" -v "$ROOT/build:/out" docker.io/library/debian:trixie bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null
    apt-get install -y -qq --no-install-recommends build-essential cmake pkg-config \
      qt6-base-dev qt6-declarative-dev qt6-multimedia-dev qt6-shadertools-dev >/dev/null
    mkdir /work && tar -C /src --exclude=./build -cf - . | tar -C /work -xf -
    cd /work
    cmake -S . -B b -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build b -j"$(nproc)" --target flowtunes
    install -m 0755 b/flowtunes /out/flowtunes'
  [[ -x $ROOT/build/$NAME ]] || { echo "container build produced no binary" >&2; exit 1; }
}

install_files() {
  mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_DIR"
  if needs_qml_wrapper; then
    mkdir -p "$PREFIX/libexec"
    install -m 0755 "$BUILT_BIN" "$PREFIX/libexec/$NAME"
    local lib_extra="$HOME/.local/lib"
    cat > "$BIN_DIR/$NAME" <<WRAP
#!/bin/bash
export LD_LIBRARY_PATH="\${LD_LIBRARY_PATH:+\$LD_LIBRARY_PATH:}$lib_extra"
export QML_IMPORT_PATH="\${QML_IMPORT_PATH:+\$QML_IMPORT_PATH:}$lib_extra/qt6/qml"
export QT_PLUGIN_PATH="\${QT_PLUGIN_PATH:+\$QT_PLUGIN_PATH:}$lib_extra/qt6/plugins"
exec "$PREFIX/libexec/$NAME" "\$@"
WRAP
    chmod 0755 "$BIN_DIR/$NAME"
    echo ">> wrapper $BIN_DIR/$NAME (QML from $lib_extra/qt6/qml)"
  else
    install -m 0755 "$BUILT_BIN" "$BIN_DIR/$NAME"
  fi
  install -m 0644 "$ROOT/share/$NAME.svg" "$ICON_DIR/$NAME.svg"
  sed -e "s|^Exec=$NAME|Exec=$BIN_DIR/$NAME|" \
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
  # Runtime packages only: the binary is already built.
  apt_build=()
  install_apt
  BUILT_BIN=$PREBUILT_BIN
else
  install_apt
  if host_can_build; then
    qt_build_ready
    echo ">> bin/build"
    "$ROOT/bin/build"
  else
    build_in_container
  fi
fi
install_files

cat <<EOF

Installed:
  binary   $BIN_DIR/$NAME
  desktop  $APP_DIR/$NAME.desktop
  icon     $ICON_DIR/$NAME.svg

Open Flowtunes from the launcher, or:
  $BIN_DIR/flowtunes [genre]

The music comes from the local model engine. If it is missing, Flowtunes offers
to set it up; install the engine first with:
  community-apps/omarchy-local-ai/install.sh

EOF
