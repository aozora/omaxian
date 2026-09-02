#!/usr/bin/env bash
# Open system monitor (btop/htop) in the i3 floating terminal helper.
set -euo pipefail

term="${HOME}/.config/i3/scripts/i3_term"
if [[ -x "$term" ]]; then
	exec "$term" -e btop
fi
if command -v btop >/dev/null 2>&1; then
	exec x-terminal-emulator -e btop
fi
exec x-terminal-emulator -e htop
