#!/usr/bin/env bash
# Host + uptime line for powermenu header.
set -euo pipefail

host="$(hostname)"
up="$(uptime -p 2>/dev/null | sed 's/^up //' || uptime | awk -F'up ' '{print $2}' | cut -d',' -f1)"
echo "${host}  ·  up ${up}"
