#!/bin/bash
# Omaxian / Debian install for omarchy-local-ai (the local model engine).
# Run from this directory, or: community-apps/omarchy-local-ai/install.sh
#
#   ./install.sh              # apt deps + engine into ~/.local
#   ./install.sh --skip-apt
#
# The engine is Python (stdlib only). It is copied to
# ~/.local/share/omarchy-local-ai and linked as omarchy-local-ai,
# omarchy-agent-local and omarchy-models in ~/.local/bin.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
SHARE_DIR="$PREFIX/share/omarchy-local-ai"

SKIP_APT=0

usage() {
  cat <<'USAGE'
Usage: install.sh [--skip-apt]

  --skip-apt   do not apt-get install deps
USAGE
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --skip-apt) SKIP_APT=1 ;;
    -h|--help) usage ;;
    # install-community-apps.sh passes this to every app; the engine is not compiled.
    --from-source) ;;
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

if (( ! SKIP_APT )); then
  if command -v apt-get >/dev/null; then
    echo ">> apt packages: ${apt_runtime[*]}"
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${apt_runtime[@]}"
  else
    echo "apt-get not found; install deps yourself (see omaxian.deps.json)" >&2
  fi
fi

if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))'; then
  echo "Python 3.11 or newer is required" >&2
  exit 1
fi

# The engine reads its catalog from the directory it runs from, so the engine and
# the catalog are always one tree. Replace the tree rather than merging into it, so
# a recipe dropped upstream does not linger.
mkdir -p "$BIN_DIR" "$PREFIX/share"
staging=$(mktemp -d "$PREFIX/share/.omarchy-local-ai.XXXXXX")
trap 'rm -rf "$staging"' EXIT
for item in agent_local.py omaxian_units.py omarchy-local-ai catalog.toml best.toml recipes runtimes reviews measurements docs README.md LICENSE; do
  cp -a "$ROOT/$item" "$staging/"
done
chmod 755 "$staging/omarchy-local-ai"
rm -rf "$SHARE_DIR"
mv "$staging" "$SHARE_DIR"
chmod 755 "$SHARE_DIR"
trap - EXIT

for name in omarchy-local-ai omarchy-agent-local omarchy-models; do
  ln -sfn "$SHARE_DIR/omarchy-local-ai" "$BIN_DIR/$name"
done

if ! grep -q "^$USER:" /etc/subuid /etc/subgid 2>/dev/null; then
  echo "!! no subordinate ids for $USER in /etc/subuid and /etc/subgid: rootless Podman needs them" >&2
fi

echo ">> installed to $SHARE_DIR; commands linked in $BIN_DIR"
echo "   omarchy-agent-local list        # recipes that fit this machine"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "   note: $BIN_DIR is not on PATH" ;;
esac
