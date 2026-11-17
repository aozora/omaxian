#!/bin/bash
# prebuilt-verify.sh — check a packaged binary runs on a clean system that has
# only the app's runtime packages (omaxian.deps.json "apt"). Catches a library
# that only a -dev package pulled in during the build, and (Qt apps) QML that
# needs a newer Qt than the 6.8 the binary targets.
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

# Qt apps: start the app headless and fail on a QML load error. ldd cannot
# see QML, which only resolves imports, types and properties at runtime;
# QML written for a newer Qt (a property 6.8 lacks) fails only here.
# start_args (omaxian.deps.json): what opens the window, for apps that are a
# command-line tool without arguments (hype: open).
qt=$(awk -F= '$1 == "qt" { print $2 }' "$DIST/$APP.env")
if [[ -n $qt ]]; then
  mapfile -t start_args < <(jq -r '.start_args // [] | .[]' "$SRC/omaxian.deps.json")
  home=$(mktemp -d)
  log="$work/start.log"
  ec=0
  # Quick 3D needs a real GL context. QT_QPA_PLATFORM=offscreen alone cannot
  # create one; xvfb + software GL (from the app's apt, e.g. libgl1-mesa-dri)
  # is enough. xvfb itself is verify-only, not a user runtime package.
  start_cmd=(timeout 15 "$work/$bin" "${start_args[@]}")
  start_env=(HOME="$home" XDG_RUNTIME_DIR="$home")
  if printf '%s\n' "${packages[@]}" | grep -qx 'qml6-module-qtquick3d'; then
    apt-get install -y --no-install-recommends xvfb xauth
    start_env+=(LIBGL_ALWAYS_SOFTWARE=1 QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl)
    start_cmd=(xvfb-run -a "${start_cmd[@]}")
  else
    start_env+=(QT_QPA_PLATFORM=offscreen)
  fi
  env "${start_env[@]}" "${start_cmd[@]}" >"$log" 2>&1 </dev/null || ec=$?
  # 124: still running when stopped, i.e. it started.
  qml_errors=$(grep -E 'QQmlApplicationEngine failed|Component is not ready|is not installed|Type [A-Za-z]+ unavailable|non-existent property|is not a type|ReferenceError|TypeError|Cannot assign' "$log" || true)
  if [[ -n $qml_errors ]] || (( ec != 124 && ec != 0 )); then
    echo "$APP: did not start on Qt $(dpkg-query -W -f '${Version}' libqt6core6t64) (exit $ec):" >&2
    cat "$log" >&2
    exit 1
  fi
  echo "$APP: starts headless with its QML loaded (Qt $(dpkg-query -W -f '${Version}' libqt6core6t64))"
fi
