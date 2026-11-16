#!/bin/bash
# Omaxian / Debian install for Meeting Recorder (standalone GTK app).
# Run from this directory, or: community-apps/omarchy-meeting-recorder/install.sh
#
#   ./install.sh                # pinned Omaxian pre-built binary when available
#   ./install.sh --from-source  # build (Vulkan) + install to ~/.local
#   ./install.sh --cpu-only     # build without Vulkan (implies --from-source)
#   ./install.sh --skip-apt     # do not apt-get install deps
#
# Pre-built binaries come from Omaxian's CI (they carry the bar-enable patch;
# upstream's release tarballs do not), pinned in .omaxian-prebuilt. Without a
# usable one the script builds. Source builds use rustup (Debian rustc is too
# old for gtk4-rs / whisper-rs).
# Upstream Arch packaging remains in install.arch.sh / packaging/aur/.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
SHARE="$PREFIX/share/omarchy-meeting-recorder"
APP_DIR="$PREFIX/share/applications"
MIME_DIR="$PREFIX/share/mime/packages"
I3_SNIPPET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/i3/config.d"
# gtk4-rs 0.11 / cairo-rs 0.22 need rustc ≥ 1.92; pin via rust-toolchain.toml
RUSTUP_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-stable}"

CPU_ONLY=0
SKIP_APT=0
FROM_SOURCE=0

usage() {
  cat <<'EOF'
Usage: install.sh [--from-source] [--cpu-only] [--skip-apt]

  (default)      pinned pre-built binary (Vulkan; runtime apt only) → ~/.local;
                 falls back to a rustup build
  --from-source  rustup build with Vulkan whisper backend → ~/.local
  --cpu-only     cargo build --no-default-features (implies --from-source)
  --skip-apt     do not apt-get install deps
  --binary       accepted for compatibility; downloading is the default now
EOF
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --cpu-only) CPU_ONLY=1; FROM_SOURCE=1 ;;
    --skip-apt) SKIP_APT=1 ;;
    --from-source) FROM_SOURCE=1 ;;
    --binary) echo "note: --binary is the default now (Omaxian-built binary)" ;;
    -h|--help) usage ;;
    *)
      echo "unknown option: $arg" >&2
      usage
      ;;
  esac
done

if [[ $(id -u) -eq 0 ]]; then
  echo "refuse to install as root — run as your login user" >&2
  exit 1
fi

# Package lists live in omaxian.deps.json (the TUI reads the same file).
# Native build deps only — Rust comes from rustup, not apt rustc/cargo.
# shellcheck source=../lib/prebuilt.sh
source "$ROOT/../lib/prebuilt.sh"
app_deps_read

# install_apt [--build] — runtime packages, plus build packages with --build.
install_apt() {
  (( SKIP_APT )) && return 0
  if ! command -v apt-get >/dev/null; then
    echo "apt-get not found; install runtime deps yourself (see omaxian.deps.json)" >&2
    return 0
  fi
  local pkgs=("${apt_runtime[@]}")
  if [[ ${1:-} == "--build" ]]; then
    pkgs+=("${apt_build[@]}")
    if (( CPU_ONLY )); then
      # glslc / vulkan headers only needed for the default Vulkan build
      local filtered=()
      local p
      for p in "${pkgs[@]}"; do
        [[ $p == glslc || $p == libvulkan-dev ]] && continue
        filtered+=("$p")
      done
      pkgs=("${filtered[@]}")
    fi
  fi
  echo ">> apt packages: ${pkgs[*]}"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}"
}

# Prefer ~/.cargo/bin over Debian /usr/bin/{rustc,cargo}.
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
    echo ">> installing rustup ($RUSTUP_TOOLCHAIN)"
    curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain "$RUSTUP_TOOLCHAIN"
    use_rustup_path
  fi
  command -v rustup >/dev/null || {
    echo "rustup not on PATH after install; open a new shell or source ~/.cargo/env" >&2
    exit 1
  }
  # Install the channel from rust-toolchain.toml (stable) so gtk4-rs builds.
  echo ">> rustup: ensure toolchain for this crate"
  (
    cd "$ROOT"
    rustup show
    # Force the directory override even if a leftover default is old.
    rustup toolchain install "$RUSTUP_TOOLCHAIN"
  )
  local ver rustc_path
  ver=$(cd "$ROOT" && rustc --version)
  rustc_path=$(cd "$ROOT" && command -v rustc)
  echo ">> $ver ($rustc_path)"
  if [[ $rustc_path != *'/.cargo/bin/'* ]]; then
    echo "error: rustc is not rustup's ($rustc_path). Put ~/.cargo/bin first on PATH." >&2
    exit 1
  fi
}

install_i3_rules() {
  mkdir -p "$I3_SNIPPET_DIR"
  local dest="$I3_SNIPPET_DIR/90_meeting-recorder.conf"
  if [[ -e $dest ]]; then
    echo "i3 rules already present: $dest"
    return 0
  fi
  cp -f "$ROOT/omaxian/i3-meeting-recorder.conf" "$dest"
  echo "installed i3 float rules → $dest (reload with: i3-msg reload)"
}

install_files() {
  local binary="$1"
  mkdir -p "$BIN_DIR" "$SHARE/plugin" "$APP_DIR" "$MIME_DIR"
  install -Dm755 "$binary" "$BIN_DIR/omarchy-meeting-recorder"
  install -Dm644 "$ROOT/data/omarchy-meeting-recorder.desktop" \
    "$APP_DIR/omarchy-meeting-recorder.desktop"
  install -Dm644 "$ROOT/data/omarchy-meeting-recorder.xml" \
    "$MIME_DIR/omarchy-meeting-recorder.xml"
  install -Dm644 "$ROOT/plugin/manifest.json" "$SHARE/plugin/manifest.json"
  install -Dm644 "$ROOT/plugin/Widget.qml" "$SHARE/plugin/Widget.qml"
  if [[ -d $ROOT/examples/actions ]]; then
    mkdir -p "$SHARE/examples/actions"
    cp -a "$ROOT/examples/actions/." "$SHARE/examples/actions/"
  fi
  # Ensure ~/.local/bin is on PATH for this login where possible
  if [[ :$PATH: != *":$BIN_DIR:"* ]]; then
    echo "note: add $BIN_DIR to PATH if the launcher cannot find omarchy-meeting-recorder"
  fi
  if command -v update-mime-database >/dev/null; then
    update-mime-database "$PREFIX/share/mime" >/dev/null 2>&1 || true
  fi
  if command -v update-desktop-database >/dev/null; then
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
  fi
  if command -v xdg-mime >/dev/null; then
    xdg-mime default omarchy-meeting-recorder.desktop application/x-omarchy-meeting >/dev/null 2>&1 || true
  fi
}

build_from_source() {
  ensure_rustup
  command -v cargo >/dev/null || {
    echo "cargo not found after rustup setup" >&2
    exit 1
  }
  local -a features=()
  if (( CPU_ONLY )); then
    features=(--no-default-features)
    echo ">> cargo build --release --no-default-features (CPU-only)"
  else
    echo ">> cargo build --release (Vulkan whisper backend)"
  fi
  (
    cd "$ROOT"
    # Explicit toolchain so Debian /usr/bin/cargo cannot sneak back in.
    cargo build --release --locked "${features[@]}"
  )
  install_files "$ROOT/target/release/omarchy-meeting-recorder"
}

if prebuilt_fetch omarchy-meeting-recorder; then
  install_apt
  install_files "$PREBUILT_BIN"
else
  install_apt --build
  build_from_source
fi

install_i3_rules

cat <<EOF

Installed:
  binary   $BIN_DIR/omarchy-meeting-recorder
  desktop  $APP_DIR/omarchy-meeting-recorder.desktop
  plugin   $SHARE/plugin/  (optional bar widget; offered on first launch)

Open Meeting Recorder from the launcher, or:
  omarchy-meeting-recorder

Optional keybinds (i3):
  bindsym \$mod+Shift+m exec --no-startup-id omarchy-meeting-recorder
  bindsym \$mod+Ctrl+m  exec --no-startup-id omarchy-meeting-recorder start

EOF
