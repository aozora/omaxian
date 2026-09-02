#!/usr/bin/env bash
# Install apt upgrades in a terminal.
set -euo pipefail

term="${HOME}/.config/i3/scripts/i3_term"
cmd='sudo apt update && sudo apt upgrade'
if [[ -x "$term" ]]; then
	exec "$term" -e bash -lc "$cmd; echo; read -r -p 'Press Enter…'"
fi
exec x-terminal-emulator -e bash -lc "$cmd; echo; read -r -p 'Press Enter…'"
