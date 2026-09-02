#!/usr/bin/env bash
# Focus an i3 container by con_id.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

con_id="${1:-}"
close_menus
[[ -n "$con_id" ]] || exit 0
i3-msg "[con_id=${con_id}] focus" >/dev/null
