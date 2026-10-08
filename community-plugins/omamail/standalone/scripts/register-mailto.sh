#!/bin/sh
# Standalone override: omamail-app.desktop is installed by standalone/install.sh,
# so there is no second launcher to write. Only the default handler is claimed.
set -eu
[ "${2:-}" = "--claim-default" ] && xdg-mime default omamail-app.desktop x-scheme-handler/mailto
exit 0
