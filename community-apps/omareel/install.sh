#!/bin/bash
# Omaxian / Debian install for Omareel (screen recorder and editor).
# Run from this directory, or: community-apps/omareel/install.sh
#
#   ./install.sh                 # pinned pre-built binary when available
#   ./install.sh --from-source   # always compile
#   ./install.sh --skip-apt
#
# Upstream is Rust (crates/, built by Corrosion) inside a Qt Quick app (CMake). Rust comes from
# rustup: Debian's rustc is older than the crates' rust-version.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
APP_DIR="$PREFIX/share/applications"
ICON_ROOT="$PREFIX/share/icons/hicolor"
NAME="omareel"
GSR_FLATPAK="com.dec05eba.gpu_screen_recorder"

SKIP_APT=0
FROM_SOURCE=0

usage() {
  cat <<'EOF'
Usage: install.sh [--from-source] [--skip-apt]

  (default)      pinned pre-built binary (runtime apt only) → ~/.local;
                 falls back to apt build deps + rustup + cmake build
  --from-source  always apt build deps + rustup + cmake build
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

use_rustup_path() {
  if [[ -f $HOME/.cargo/env ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
  fi
  export PATH="$HOME/.cargo/bin:$PATH"
}

ensure_rustup() {
  use_rustup_path
  if ! command -v rustup >/dev/null; then
    echo ">> installing rustup"
    curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain none --profile minimal
    use_rustup_path
  fi
  command -v rustup >/dev/null || {
    echo "rustup not on PATH after install; source ~/.cargo/env" >&2
    exit 1
  }
  echo ">> rustup: toolchain from rust-toolchain.toml"
  (cd "$ROOT" && rustup show active-toolchain)
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
# app through a wrapper that points at it, as Folio and Flowtunes do.
needs_qml_wrapper() {
  local sys=/usr/lib/x86_64-linux-gnu/qt6/qml
  local local_qml=$HOME/.local/lib/qt6/qml
  [[ -d $local_qml/QtMultimedia && ! -d $sys/QtMultimedia ]]
}

# The export's colour conversion is a shader compiled by Qt ShaderTools at
# build time. A local Qt overlay (~/.local/opt/omaxian-qt6-<mm>) often has no
# ShaderTools, and apt only offers Qt 6.8. A binary built against Qt 6.8 runs
# on 6.8 and newer, so build it in a Debian trixie container instead.
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
  "$engine" run --rm -v "$ROOT/..:/apps:ro" -v "$ROOT/build:/out" docker.io/library/debian:trixie bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
    apt-get update -qq >/dev/null
    apt-get install -y -qq --no-install-recommends jq >/dev/null
    mapfile -t packages < <(jq -r "(.apt // []) + (.apt_build // []) | .[]" /apps/omareel/omaxian.deps.json)
    apt-get install -y -qq --no-install-recommends "${packages[@]}" >/dev/null
    curl --proto "=https" --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y -q --default-toolchain none --profile minimal >/dev/null
    mkdir /work && tar -C /apps/omareel --exclude=./build --exclude=./target -cf - . | tar -C /work -xf -
    cd /work
    BUILD_DIR=/work/b bin/build -DBUILD_TESTING=OFF
    install -m 0755 b/omareel /out/omareel'
  [[ -x $ROOT/build/$NAME ]] || { echo "container build produced no binary" >&2; exit 1; }
}

gsr_available() {
  command -v gpu-screen-recorder >/dev/null && return 0
  command -v flatpak >/dev/null && flatpak info "$GSR_FLATPAK" >/dev/null 2>&1
}

install_files() {
  mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_ROOT/scalable/apps"
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
  # Upstream's legacy command name.
  ln -sfn "$NAME" "$BIN_DIR/omarecord"
  install -m 0644 "$ROOT/pkg/$NAME.svg" "$ICON_ROOT/scalable/apps/$NAME.svg"
  local size
  for size in 16 32 48 64 128 256 512; do
    install -Dm 0644 "$ROOT/pkg/icons/$NAME-$size.png" "$ICON_ROOT/${size}x${size}/apps/$NAME.png"
  done
  sed -e "s|^Exec=$NAME|Exec=$BIN_DIR/$NAME|" \
    "$ROOT/pkg/$NAME.desktop" > "$APP_DIR/$NAME.desktop"
  chmod 0644 "$APP_DIR/$NAME.desktop"
  if command -v update-desktop-database >/dev/null; then
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null; then
    gtk-update-icon-cache -q -t -f "$ICON_ROOT" >/dev/null 2>&1 || true
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
    ensure_rustup
    echo ">> bin/build"
    "$ROOT/bin/build" -DBUILD_TESTING=OFF
  else
    build_in_container
  fi
fi
install_files

cat <<EOF

Installed:
  binary   $BIN_DIR/$NAME (and the legacy name omarecord)
  desktop  $APP_DIR/$NAME.desktop
  icons    $ICON_ROOT/*/apps/$NAME.*

Open Omareel from the launcher, or bind the recording toggle in i3:
  bindsym \$mod+Mod1+r exec --no-startup-id $BIN_DIR/$NAME record

EOF

if ! gsr_available; then
  cat <<EOF
Recording needs gpu-screen-recorder, which is not installed. Install the Flatpak
that Omaxian's screen recorder uses:
  flatpak install flathub $GSR_FLATPAK

EOF
fi
if ! id -nG | tr ' ' '\n' | grep -qx input; then
  cat <<EOF
Clicks and keystrokes are read from /dev/input, which needs the input group:
  sudo adduser $USER input    # then log out and back in

EOF
fi
