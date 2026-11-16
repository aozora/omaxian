#!/bin/bash
# prebuilt-verify.sh — check a packaged binary runs on a clean system that has
# only the app's runtime packages (omaxian.deps.json "apt"). Catches a library
# that only a -dev package pulled in during the build.
# Runs as root inside a fresh debian:trixie container.
#
#   .github/scripts/prebuilt-verify.sh <app> <dist dir>

set -euo pipefail

APP="${1:?usage: prebuilt-verify.sh <app> <dist dir>}"
DIST="${2:?usage: prebuilt-verify.sh <app> <dist dir>}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$REPO_DIR/community-apps/$APP"

file=$(awk -F= '$1 == "file" { print $2 }' "$DIST/$APP.env")
bin=$(awk -F= '$1 == "bin" { print $2 }' "$DIST/$APP.env")

mapfile -t packages < <(jq -r '.apt // [] | .[]' "$SRC/omaxian.deps.json")
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends "${packages[@]}"

work=$(mktemp -d)
tar -xzf "$DIST/$file" -C "$work"
missing=$(ldd "$work/$bin" | grep 'not found' || true)
if [[ -n $missing ]]; then
  echo "$APP: libraries missing with only its runtime packages installed:" >&2
  echo "$missing" >&2
  echo "Add the providing packages to community-apps/$APP/omaxian.deps.json \"apt\"." >&2
  exit 1
fi
echo "$APP: every library resolves with runtime packages only"
