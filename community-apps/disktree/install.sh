#!/bin/bash
# Omaxian / Debian install for disktree (GPUI disk treemap).
# Run from this directory, or: community-apps/disktree/install.sh
#
#   ./install.sh                 # pinned upstream release binary (x86_64)
#   ./install.sh --from-source   # rustup + make install
#   ./install.sh --skip-apt
#
# The default downloads the upstream release pinned in .omaxian-prebuilt and
# checks its sha256 (Omaxian's disktree changes are packaging-only). It falls
# back to building when there is no usable binary. Source builds embed static
# musl disktree-scan helpers (SSH scans); Rust comes from rustup, not Debian.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
I3_SNIPPET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/i3/config.d"
# Passed to make explicitly: its `?=` defaults would pick up unrelated env
# vars (an AppImage terminal exports APPDIR).
MAKE_DIRS=(
  PREFIX="$PREFIX"
  BINDIR="$PREFIX/bin"
  APPDIR="$PREFIX/share/applications"
  ICONDIR="$PREFIX/share/icons/hicolor/scalable/apps"
)

SKIP_APT=0
FROM_SOURCE=0

usage() {
  cat <<'EOF'
Usage: install.sh [--from-source] [--skip-apt]

  (default)      pinned release binary → ~/.local; builds when none is usable
  --from-source  apt build deps, rustup 1.97, make install to ~/.local
  --skip-apt     do not apt-get install deps
  Also installs the i3 float rule when missing.
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
  # Must run inside the tree. rust-toolchain.toml selects 1.97, and
  # `rustup target add` from anywhere else installs the musl stdlib for the
  # default toolchain only. cargo then cannot find `core` for that triple.
  echo ">> rustup target add musl helpers for $(cd "$ROOT" && rustc --version)"
  (
    cd "$ROOT"
    rustup target add x86_64-unknown-linux-musl aarch64-unknown-linux-musl
  )
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

# The Makefile's Linux `install` recipe, without make: build-essential (and
# so make) is only installed for source builds, and a minimal Devuan has no
# make. Keep in step with the Makefile's install target.
install_prebuilt() {
  local bin="$1" bindir="$PREFIX/bin" appdir="$PREFIX/share/applications"
  local icondir="$PREFIX/share/icons/hicolor/scalable/apps" version
  version=$(sed -n 's/^version = "\(.*\)"/\1/p' "$ROOT/Cargo.toml" | head -1)
  echo ">> install pre-built disktree $version → $PREFIX"
  install -d "$bindir" "$appdir" "$icondir"
  install -m 0755 "$bin" "$bindir/disktree"
  install -m 0644 "$ROOT/assets/disktree.svg" "$icondir/disktree.svg"
  sed -e "s|@BINDIR@|$bindir|" -e "s|@VERSION@|$version|" \
    "$ROOT/packaging/disktree.desktop.in" > "$appdir/disktree.desktop"
  chmod 0644 "$appdir/disktree.desktop"
  if command -v update-desktop-database >/dev/null; then
    update-desktop-database "$appdir" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null; then
    gtk-update-icon-cache -q -t -f "$PREFIX/share/icons/hicolor" >/dev/null 2>&1 || true
  fi
}

if prebuilt_fetch disktree; then
  install_apt
  install_prebuilt "$PREBUILT_BIN"
else
  install_apt --build
  ensure_rustup
  echo ">> make install PREFIX=$PREFIX"
  make -C "$ROOT" install "${MAKE_DIRS[@]}"
fi
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
