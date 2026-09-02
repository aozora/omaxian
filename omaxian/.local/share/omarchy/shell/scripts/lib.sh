#!/usr/bin/env bash
# Shared helpers for quickshell bar scripts, mirroring eww/scripts/lib.sh's
# call shape so scripts copied from eww (network-menu.sh, bluetooth-menu.sh)
# work unchanged. close_menus() is a no-op here: quickshell popups close
# themselves via Bar.qml's activePopout coordinator (see docs/quickshell/
# README.md), there's no bash-level "close every popup window" step needed
# the way eww's `eww close <window>` calls were.
set -euo pipefail

close_menus_except() { :; }
close_menus() { :; }
