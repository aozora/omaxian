#!/bin/bash
# Omaxian / Debian install for disktree (GPUI disk treemap).
# Run from this directory, or: community-apps/disktree/install.sh
#
#   ./install.sh
#   ./install.sh --skip-apt
#
# Linux `make install` builds the GUI and embeds static musl disktree-scan
# helpers (SSH scans). Rust comes from rustup, not Debian rustc.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
I3_SNIPPET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/i3/config.d"

SKIP_APT=0

usage() {
  cat <<'EOF'
Usage: install.sh [--skip-apt]

  (default)  apt deps, rustup 1.97, make install to ~/.local, i3 float rule if missing
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
  libvulkan1
  libx11-6
  libxcb1
  libxkbcommon0
  libxkbcommon-x11-0
  libwayland-client0
  libfontconfig1
  libfreetype6
)
apt_build=(
  build-essential
  pkg-config
  libvulkan-dev
  libx11-dev
  libxcb1-dev
  libxkbcommon-dev
  libxkbcommon-x11-dev
  libwayland-dev
  libfontconfig-dev
  libfreetype-dev
)

install_apt() {
  (( SKIP_APT )) && return 0
  if ! command -v apt-get >/dev/null; then
    echo "apt-get not found; install deps yourself (see omaxian.deps.json)" >&2
    return 0
  fi
  echo ">> apt packages: ${apt_runtime[*]} ${apt_build[*]}"
  sudo apt-get install -y --no-install-recommends "${apt_runtime[@]}" "${apt_build[@]}"
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
    curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y
    use_rustup_path
  fi
  command -v rustup >/dev/null || {
    echo "rustup not on PATH after install; source ~/.cargo/env" >&2
    exit 1
  }
  echo ">> rustup: toolchain from rust-toolchain.toml"
  (
    cd "$ROOT"
    rustup show
  )
  local rustc_path
  rustc_path=$(cd "$ROOT" && command -v rustc)
  echo ">> $(cd "$ROOT" && rustc --version) ($rustc_path)"
  if [[ $rustc_path != *'/.cargo/bin/'* ]]; then
    echo "error: rustc is not rustup's ($rustc_path). Put ~/.cargo/bin first on PATH." >&2
    exit 1
  fi
  echo ">> rustup target add musl helpers"
  rustup target add x86_64-unknown-linux-musl aarch64-unknown-linux-musl
}

install_i3_rules() {
  mkdir -p "$I3_SNIPPET_DIR"
  local dest="$I3_SNIPPET_DIR/90_disktree.conf"
  if [[ -e $dest ]]; then
    echo "i3 rules already present: $dest"
    return 0
  fi
  cp -f "$ROOT/omaxian/i3-disktree.conf" "$dest"
  echo "installed i3 float rules → $dest (reload with: i3-msg reload)"
}

install_apt
ensure_rustup
echo ">> make install PREFIX=$PREFIX"
make -C "$ROOT" install PREFIX="$PREFIX"
install_i3_rules

cat <<EOF

Installed:
  binary   $PREFIX/bin/disktree
  desktop  $PREFIX/share/applications/disktree.desktop
  icon     $PREFIX/share/icons/hicolor/scalable/apps/disktree.svg

Open disktree from the launcher, or:
  $PREFIX/bin/disktree

If the float rule was just added: i3-msg reload

EOF
