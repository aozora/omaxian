#!/usr/bin/env bash
## Hook after display layout apply / i3 start.
##
## i3 already keeps exactly one visible workspace per output. Do not move
## workspace 1 onto the primary — that steals it from the other monitor.
## Optional number-to-output pins belong in a local
## ~/.config/i3/config.d/90_outputs.conf (see docs/omaxian/customize/displays.md).

exit 0
