#!/bin/bash
# prebuilt-manifests.sh — write community-apps/<app>/.omaxian-prebuilt for
# every <app>.env in a dist directory, pointing at a release tag.
# Used by .github/workflows/community-apps.yml after the release upload.
#
#   .github/scripts/prebuilt-manifests.sh <dist dir> <repo owner/name> <tag> <tree sha>

set -euo pipefail

DIST="${1:?usage: prebuilt-manifests.sh <dist> <repo> <tag> <tree sha>}"
REPO="${2:?}"
TAG="${3:?}"
TREE="${4:?}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

shopt -s nullglob
for env in "$DIST"/*.env; do
  app=$(basename "$env" .env)
  get() { awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$env"; }
  {
    echo "# Pre-built binary for install.sh (see community-apps/lib/prebuilt.sh)."
    echo "# Written by .github/workflows/community-apps.yml — do not edit by hand."
    echo "url=https://github.com/$REPO/releases/download/$TAG/$(get file)"
    echo "sha256=$(get sha256)"
    echo "tree=$TREE"
    echo "src=$(get src)"
    echo "bin=$(get bin)"
    echo "arch=$(get arch)"
    if [[ -n $(get qt) ]]; then
      echo "qt=$(get qt)"
    fi
  } > "$REPO_DIR/community-apps/$app/.omaxian-prebuilt"
  echo "wrote community-apps/$app/.omaxian-prebuilt"
done
