#!/usr/bin/env bash

## Copyright (C) 2020-2026 Aditya Shakya <adi1090x@gmail.com>
##
## Apply wallpaper on i3 startup

CURRENT_BACKGROUND="$HOME/.local/state/omarchy/current/background"
DEFAULT_WALLPAPER="$HOME/.config/i3/wallpaper"

## Prefer the last theme/wallpaper-picker selection; fall back to the seeded
## default when nothing has set the symlink yet (e.g. first-ever run).
if [[ -e $CURRENT_BACKGROUND ]]; then
	WALLPAPER="$CURRENT_BACKGROUND"
else
	WALLPAPER="$DEFAULT_WALLPAPER"
fi

## For single monitor
#hsetroot -root -cover "$WALLPAPER"

## For all monitors
hsetroot -cover "$WALLPAPER"
