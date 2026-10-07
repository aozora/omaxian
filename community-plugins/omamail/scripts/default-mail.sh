#!/bin/sh
# Makes Omamail the desktop's mail client, or hands the job back.
#
#   default-mail.sh on <plugin-dir>   claim mailto: and Mod4+Shift+e
#   default-mail.sh off               remove Omamail's i3 binds
#   default-mail.sh status            print `default` or `not-default`
#
# Two things decide "which mail client" on Omaxian, and a switch that moved
# only one would leave the other opening something else:
#
#   - the x-scheme-handler/mailto default, which register-mailto.sh owns
#   - Mod4+Shift+e and Mod4+Shift+Mod1+e, written as a managed drop-in under
#     ~/.config/i3/config.d/ (included by the stock i3 config)
#
# Omaxian does not ship a stock email bind for those chords (upstream Omarchy
# uses Hyprland bindings.lua for HEY). `off` deletes the drop-in; the mailto
# default stays with Omamail because nothing else claims it back.
#
# Omaxian port: i3 config.d + i3-msg reload (upstream: Hyprland bindings.lua).
set -eu

CONFIG_HOME=${XDG_CONFIG_HOME:-${HOME:?}/.config}
BINDINGS_FILE="$CONFIG_HOME/i3/config.d/99-omamail-default-mail.conf"
BLOCK_BEGIN="# >>> omamail default mail client, do not edit by hand"
BLOCK_END="# <<< omamail default mail client"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

usage() {
  fail 'usage: default-mail.sh on <plugin-dir> | off | status'
}

bindings_block() {
  cat <<EOF
$BLOCK_BEGIN
bindsym Mod4+Shift+e exec --no-startup-id omarchy-shell shell summon omamail '{}'
bindsym Mod4+Shift+Mod1+e exec --no-startup-id omarchy-shell shell summon omamail '{"compose":true}'
$BLOCK_END
EOF
}

has_block() {
  [ -f "$BINDINGS_FILE" ] && grep -qxF -- "$BLOCK_BEGIN" "$BINDINGS_FILE"
}

remove_block() {
  [ -f "$BINDINGS_FILE" ] || return 0
  rm -f "$BINDINGS_FILE"
}

add_block() {
  mkdir -p "$(dirname "$BINDINGS_FILE")"
  bindings_block > "$BINDINGS_FILE"
}

reload_i3() {
  if command -v i3-msg >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    i3-msg -t command reload >/dev/null 2>&1 || true
  fi
}

mailto_default() {
  command -v xdg-mime >/dev/null 2>&1 || return 0
  xdg-mime query default x-scheme-handler/mailto 2>/dev/null || true
}

case "${1:-}" in
  on)
    [ "$#" -eq 2 ] || usage
    plugin_dir=$(cd "$2" && pwd)
    sh "$plugin_dir/scripts/register-mailto.sh" "$plugin_dir" --claim-default
    add_block
    reload_i3
    printf '%s\n' 'Omamail is now the default mail client.'
    printf '%s\n' 'Mod4+Shift+e opens Omamail; Mod4+Shift+Mod1+e starts a new message.'
    ;;
  off)
    [ "$#" -eq 1 ] || usage
    remove_block
    reload_i3
    printf '%s\n' "Omamail's Mod4+Shift+e binding is removed."
    ;;
  status)
    [ "$#" -eq 1 ] || usage
    if has_block && [ "$(mailto_default)" = omamail.desktop ]; then
      printf '%s\n' default
    else
      printf '%s\n' not-default
    fi
    ;;
  *) usage ;;
esac
