#!/bin/sh
# default-mail.sh claims mailto: and Mod4+Shift+e, and undoing it must leave
# no managed i3 drop-in behind. Runs against a throwaway config and data home;
# i3 is never reloaded (no DISPLAY).
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/scripts/default-mail.sh"
fail() { printf 'test_default_mail.sh: %s\n' "$1" >&2; exit 1; }

[ -x "$script" ] || fail "scripts/default-mail.sh must be executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_CONFIG_HOME="$tmp/config" XDG_DATA_HOME="$tmp/data" DISPLAY=
bindings="$XDG_CONFIG_HOME/i3/config.d/99-omamail-default-mail.conf"
mkdir -p "$(dirname "$bindings")"

[ "$(sh "$script" status)" = not-default ] || fail "a fresh config must not report default"
[ ! -f "$bindings" ] || fail "a fresh config must not already have the drop-in"

sh "$script" on "$root" >/dev/null
[ -f "$bindings" ] || fail "on must write the i3 drop-in"
grep -qF "bindsym Mod4+Shift+e exec --no-startup-id omarchy-shell shell summon omamail '{}'" "$bindings" \
  || fail "on must bind Mod4+Shift+e to summon Omamail"
grep -qF 'compose' "$bindings" || fail "on must bind Mod4+Shift+Mod1+e to a new message"
[ -f "$XDG_DATA_HOME/applications/omamail.desktop" ] || fail "on must register omamail.desktop"
if command -v xdg-mime >/dev/null 2>&1; then
  [ "$(sh "$script" status)" = default ] || fail "on must report default"
fi

sh "$script" on "$root" >/dev/null
[ "$(grep -c 'omamail default mail client, do not edit' "$bindings")" = 1 ] \
  || fail "a second on must not add a second block"

sh "$script" off >/dev/null
[ ! -f "$bindings" ] || fail "off must remove the i3 drop-in"
[ "$(sh "$script" status)" = not-default ] || fail "off must report not-default"

if sh "$script" bogus >/dev/null 2>&1; then fail "an unknown action must fail"; fi

printf 'test_default_mail.sh ok\n'
