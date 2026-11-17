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

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
APP_DIR="$PREFIX/share/applications"
ICON_DIR="$PREFIX/share/icons/hicolor/scalable/apps"
NAME="checkmate"

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
  echo "No Qt6 cmake config found. Install qt6-base-dev + qt6-declarative-dev + qt6-quick3d-dev, or a matching ~/.local/opt/omaxian-qt6-<mm>/." >&2
  exit 1
}

install_files() {
  mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_DIR"
  install -m 0755 "$BUILT_BIN" "$BIN_DIR/$NAME"
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
  # Runtime packages only: the binary is already built.
  apt_build=()
  install_apt
  BUILT_BIN=$PREBUILT_BIN
else
  install_apt
  qt_build_ready
  echo ">> bin/build"
  "$ROOT/bin/build"
fi
install_files

cat <<EOF

Installed:
  binary   $BIN_DIR/$NAME
  desktop  $APP_DIR/$NAME.desktop
  icon     $ICON_DIR/$NAME.svg

Open Checkmate from the launcher, or:
  $BIN_DIR/checkmate open

Headless: $BIN_DIR/checkmate inspect | export | legal [FEN]

EOF
