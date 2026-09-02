#!/usr/bin/env bash
# Run a shell command (rofi runner replacement).
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

cmd="${1:-}"
close_menus
[[ -n "$cmd" ]] || exit 0
nohup bash -lc "$cmd" >/dev/null 2>&1 &
