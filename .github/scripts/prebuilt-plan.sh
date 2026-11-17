#!/bin/bash
# prebuilt-plan.sh — print (as a JSON array) the community apps whose pinned
# binary is missing or stale. Used by .github/workflows/community-apps.yml.
#
#   .github/scripts/prebuilt-plan.sh            # stale apps only
#   .github/scripts/prebuilt-plan.sh omacalc …  # these apps, stale or not
#
# Stale = no .omaxian-prebuilt, or <app>/ changed since its tree= commit
# (ignoring files that only affect installing; see community-apps/lib/prebuilt.sh).
# Needs a full clone (fetch-depth: 0) so tree= commits resolve.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPS_DIR="$REPO_DIR/community-apps"

# Apps Omaxian builds itself. disktree pins upstream's release instead
# (its Omaxian changes are packaging-only).
CI_APPS=(folio hype monologue omacalc omacut omarchy-meeting-recorder omaview omawrite plain signed)

IGNORE=(
  ':(exclude).omaxian-prebuilt'
  ':(exclude)install.sh'
  ':(exclude)omaxian.deps.json'
  ':(exclude)*.md'
)

is_ci_app() {
  local app
  for app in "${CI_APPS[@]}"; do
    [[ $app == "$1" ]] && return 0
  done
  return 1
}

is_stale() {
  local dir="$APPS_DIR/$1" tree
  [[ -f $dir/.omaxian-prebuilt ]] || return 0
  tree=$(awk -F= '$1 == "tree" { print $2; exit }' "$dir/.omaxian-prebuilt")
  [[ -n $tree ]] || return 0
  git -C "$dir" cat-file -e "$tree^{commit}" 2>/dev/null || return 0
  ! git -C "$dir" diff --quiet "$tree" HEAD -- . "${IGNORE[@]}"
}

selected=()
if (( $# > 0 )); then
  for app in "$@"; do
    if ! is_ci_app "$app"; then
      echo "not built by CI: $app (known: ${CI_APPS[*]})" >&2
      exit 1
    fi
    selected+=("$app")
  done
else
  for app in "${CI_APPS[@]}"; do
    if is_stale "$app"; then
      selected+=("$app")
    fi
  done
fi

if (( ${#selected[@]} == 0 )); then
  echo '[]'
else
  printf '%s\n' "${selected[@]}" | jq -R . | jq -sc .
fi
