#!/bin/bash
# qmllint-qt68.sh — lint community-app QML against Qt 6.8 (Devuan Excalibur).
#
#   community-apps/lib/qmllint-qt68.sh            # every app with QML
#   community-apps/lib/qmllint-qt68.sh folio …    # these apps
#
# Pre-built binaries are built against Qt 6.8 and must run there. C++ written
# for a newer Qt fails to compile, but QML only fails when it loads: a type,
# property or enum added after 6.8 (Flickable.acceptedButtons,
# VideoOutput.mirrored, …) builds fine and then the app will not start on
# Excalibur. This runs qmllint with Debian trixie's Qt 6.8 QML modules
# (podman or docker) and reports [missing-property] findings.
#
# Only QML compiled into the app (<app>/src) is linted; Quickshell bar widgets
# (e.g. omarchy-meeting-recorder/plugin) run on the shell's Qt, not 6.8.
#
# To use a newer-Qt property while still running on 6.8, set it from
# JavaScript behind a check on the same line, e.g.
#   Component.onCompleted: if (view.acceptedButtons !== undefined) view.acceptedButtons = Qt.NoButton
# Lines containing "!== undefined" are not reported, unless the guard reads a
# bare name (qmllint [unqualified]): on 6.8 that throws a ReferenceError
# rather than giving undefined, and the rest of the handler is skipped.
#
# Known false positives are dropped: Qt.application typed as its base class,
# and untyped lookups on QQuickItem / QObject. Properties of an app's own C++
# types (which qmllint cannot see) go in lib/qmllint-ignore.txt after review.
# Exit 1 when anything is left. CI's verify step (headless start) is the final
# check; this is the fast one to run while porting or bumping upstream.

set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$(cd "$LIB/.." && pwd)"
IGNORE_FILE="$LIB/qmllint-ignore.txt"
IMAGE="docker.io/library/debian:trixie"

engine=""
for e in podman docker; do
  if command -v "$e" >/dev/null; then engine=$e; break; fi
done
[[ -n $engine ]] || { echo "needs podman or docker" >&2; exit 2; }
command -v jq >/dev/null || { echo "needs jq" >&2; exit 2; }

apps=("$@")
if (( ${#apps[@]} == 0 )); then
  for d in "$APPS_DIR"/*/; do
    d=$(basename "$d")
    [[ $d == "lib" ]] && continue
    if [[ -d $APPS_DIR/$d/src && -n $(find "$APPS_DIR/$d/src" -name '*.qml' -print -quit) ]]; then
      apps+=("$d")
    fi
  done
fi

# Qt packages the apps run with, plus the linter.
mapfile -t packages < <(
  for a in "${apps[@]}"; do
    jq -r '.apt // [] | .[]' "$APPS_DIR/$a/omaxian.deps.json"
  done | grep -E '^(qml6-module-|libqt6|qt6-)' | sort -u
)
packages+=(qt6-declarative-dev-tools)

raw=$("$engine" run --rm -e APPS="${apps[*]}" -v "$APPS_DIR:/apps:ro,Z" -w /apps "$IMAGE" bash -c '
  set -e
  apt-get update -qq >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$@" >/dev/null 2>&1
  echo "# Qt $(dpkg-query -W -f "\${Version}" libqt6core6t64)" >&2
  for app in $APPS; do
    [ -d "$app/src" ] || continue
    find "$app/src" -name "*.qml" | sort | while read -r f; do
      /usr/lib/qt6/bin/qmllint -I "$(dirname "$f")" "$f" 2>&1 | grep -E "\[(missing-property|unqualified)\]" || true
    done
  done
' lint "${packages[@]}" 2>&1 | sed 's/^Warning: //')

# The container prints its Qt version to stderr, merged above.
grep '^# Qt' <<<"$raw" || true
unqualified=$(grep '\[unqualified\]' <<<"$raw" || true)
findings=$(grep -v '^# Qt' <<<"$raw" | grep -v '\[unqualified\]' \
  | grep -vE 'not found on type "(QQmlApplication|QQuickItem|QObject)"' || true)

# Ignore entries: <file>|<message text>, matched on lines for that file.
if [[ -f $IGNORE_FILE && -n $findings ]]; then
  findings=$(awk -F'|' '
    NR == FNR { if ($0 !~ /^#/ && NF == 2) { file[++n] = $1; msg[n] = $2 } next }
    { for (i = 1; i <= n; i++) if (index($0, file[i] ":") == 1 && index($0, msg[i])) next; print }
  ' "$IGNORE_FILE" - <<<"$findings")
fi

# Guarded access (same line has "!== undefined"): intended, see the header.
guarded() {
  local loc="${1%%: *}" file line
  file="${loc%%:*}"; line="${loc#*:}"; line="${line%%:*}"
  [[ -f $APPS_DIR/$file ]] && sed -n "${line}p" "$APPS_DIR/$file" | grep -qF '!== undefined'
}
kept=""
while IFS= read -r f; do
  [[ -z $f ]] && continue
  guarded "$f" || kept+="$f"$'\n'
done <<<"$findings"
# A guard on a bare name: report it even though the line is "guarded".
while IFS= read -r f; do
  [[ -z $f ]] && continue
  guarded "$f" && kept+="${f/Unqualified access/Guard reads a bare name; use <id>.<property> !== undefined}"$'\n'
done <<<"$unqualified"
findings=$(sed '/^$/d' <<<"$kept" | sort -u)

if [[ -n $findings ]]; then
  echo "QML that Qt 6.8 cannot load (or new C++-type false positives for lib/qmllint-ignore.txt):"
  echo "$findings"
  exit 1
fi
echo "qmllint (Qt 6.8): ${apps[*]} clean"
