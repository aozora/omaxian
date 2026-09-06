#!/usr/bin/env bash

## Copyright (C) 2020-2026 Aditya Shakya <adi1090x@gmail.com>
##
## Apply wallpaper on i3 startup

CURRENT_BACKGROUND="$HOME/.local/state/omarchy/current/background"

## Restore the last theme / wallpaper-picker selection. Nothing to do on a
## first-ever run before any theme has set the symlink.
[[ -e $CURRENT_BACKGROUND ]] || exit 0

hsetroot -cover "$CURRENT_BACKGROUND"
