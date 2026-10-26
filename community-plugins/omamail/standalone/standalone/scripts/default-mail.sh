#!/bin/sh
# Standalone override of default-mail.sh (on <dir> | off | status). Only the
# x-scheme-handler/mailto default is managed; no i3 binds are written.
set -eu
case "${1:-}" in
  on) xdg-mime default omamail-app.desktop x-scheme-handler/mailto ;;
  off) ;;
  status)
    if [ "$(xdg-mime query default x-scheme-handler/mailto 2>/dev/null)" = omamail-app.desktop ]; then
      echo default
    else
      echo not-default
    fi ;;
  *) echo 'usage: default-mail.sh on <dir> | off | status' >&2; exit 2 ;;
esac
