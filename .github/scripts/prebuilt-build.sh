#!/bin/bash
# prebuilt-build.sh — build one community app and package its binary.
# Runs as root inside a debian:trixie container (Qt 6.8, the oldest Qt the
# binaries support). Used by .github/workflows/community-apps.yml.
#
#   .github/scripts/prebuilt-build.sh <app> <out dir>
#
# Writes to <out dir>:
#   <app>-<sha7>-<arch>-linux.tar.gz   one directory holding the binary only
#   <app>.env                          file=, sha256=, src=, bin=, arch=, qt=
# install.sh takes everything else (.desktop, icons, plugins) from the tree.

set -euo pipefail

APP="${1:?usage: prebuilt-build.sh <app> <out dir>}"
OUT="${2:?usage: prebuilt-build.sh <app> <out dir>}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$REPO_DIR/community-apps/$APP"
ARCH="$(uname -m)"
SHA="$(git -C "$REPO_DIR" rev-parse HEAD)"
NAME="$APP-${SHA:0:7}-$ARCH-linux"

[[ -f $SRC/install.sh ]] || { echo "unknown app: $APP" >&2; exit 1; }
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

echo "::group::apt (runtime + build)"
mapfile -t packages < <(jq -r '(.apt // []) + (.apt_build // []) | .[]' "$SRC/omaxian.deps.json")
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends "${packages[@]}"
echo "::endgroup::"

install_rustup() {
  echo "::group::rustup (rust-toolchain.toml)"
  curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain none --profile minimal
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env"
  (cd "$SRC" && rustup show)
  echo "::endgroup::"
}

# A Cargo.toml with a bin/build beside it is a Qt app with Rust inside (omareel):
# CMake builds it and links the crates in, so it takes the Qt branch below.
if [[ -f $SRC/Cargo.toml && ! -x $SRC/bin/build ]]; then
  install_rustup
  echo "::group::cargo build"
  (cd "$SRC" && cargo build --release --locked)
  echo "::endgroup::"
  BIN="$SRC/target/release/$APP"
  QT=""
elif [[ -f $SRC/go.mod ]]; then
  # Go (Wails) apps: bin/build builds the frontend and the binary; no Qt.
  echo "::group::bin/build"
  "$SRC/bin/build"
  echo "::endgroup::"
  BIN="$SRC/build/$APP"
  QT=""
else
  [[ -f $SRC/Cargo.toml ]] && install_rustup
  echo "::group::bin/build"
  "$SRC/bin/build"
  echo "::endgroup::"
  BIN="$SRC/build/$APP"
  # Oldest Qt the binary runs on = the Qt it was built against (major.minor).
  QT=$(dpkg-query -W -f '${Version}' libqt6core6t64)
  QT=${QT%%[+-]*}
  QT=${QT%.*}
fi

[[ -x $BIN ]] || { echo "build produced no $BIN" >&2; exit 1; }

mkdir -p "$OUT/$NAME"
install -m 0755 "$BIN" "$OUT/$NAME/$APP"
strip --strip-unneeded "$OUT/$NAME/$APP" || true
tar -C "$OUT" --owner=0 --group=0 --numeric-owner -czf "$OUT/$NAME.tar.gz" "$NAME"
rm -rf "${OUT:?}/$NAME"

# The installer's staleness check (works in a shallow clone too).
ROOT="$SRC"
# shellcheck source=../../community-apps/lib/prebuilt.sh
source "$REPO_DIR/community-apps/lib/prebuilt.sh"
SRC_HASH=$(prebuilt_src_hash "$SRC")

cat > "$OUT/$APP.env" <<EOF
file=$NAME.tar.gz
sha256=$(sha256sum "$OUT/$NAME.tar.gz" | awk '{ print $1 }')
src=$SRC_HASH
bin=$NAME/$APP
arch=$ARCH
qt=$QT
EOF
cat "$OUT/$APP.env"
