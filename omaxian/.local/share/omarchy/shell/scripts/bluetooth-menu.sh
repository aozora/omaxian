#!/usr/bin/env bash
# Open the Bluetooth manager (blueman).
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

close_menus

if command -v blueman-manager >/dev/null 2>&1; then
	exec blueman-manager
fi
