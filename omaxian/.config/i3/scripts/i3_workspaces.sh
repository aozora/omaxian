#!/usr/bin/env bash
## Focus workspace 1 on the primary output after display layout is applied.
## Fixes polybar (pin-workspaces) showing workspace 2 first on multi-monitor setups.

sleep 0.3

command -v i3-msg >/dev/null 2>&1 || exit 0
command -v xrandr >/dev/null 2>&1 || exit 0

primary=$(xrandr --query 2>/dev/null | awk '/ connected primary/{print $1; exit}')
[[ -z "$primary" ]] && primary=$(xrandr --query 2>/dev/null | awk '/ connected/{print $1; exit}')

if [[ -n "$primary" ]]; then
	i3-msg "workspace number 1; move workspace to output $primary; workspace number 1" >/dev/null
fi
