#!/bin/sh
# Standalone override: hand the mailto: URL to omamail-app, not omarchy-shell.
exec omamail-app "$@"
