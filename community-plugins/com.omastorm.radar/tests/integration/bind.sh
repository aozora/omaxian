#!/usr/bin/env bash
# Documented global key (DESIGN.md, global keybinding): README names an i3
# chord and the shell toggle; install and launch never write i3 config.
set -euo pipefail
# shellcheck source=tests/integration/common.sh
source "$(dirname "$0")/common.sh"
cd "$(dirname "$0")/../.."

bind='bindsym $mod+Shift+r exec --no-startup-id omarchy-shell shell toggle com.omastorm.radar '"'"'{}'"'"''
rg -F -- "$bind" README.md >/dev/null \
  || fail "README.md does not name the documented i3 bindsym line"
rg -F -- 'omarchy-shell shell toggle com.omastorm.radar' README.md >/dev/null \
  || fail 'README.md does not name omarchy-shell shell toggle com.omastorm.radar'
rg -F -- 'community-plugins/com.omastorm.radar' README.md >/dev/null \
  || fail 'README.md does not name the local community-plugins install path'

# Omastorm never writes compositor config, and neither do install or launch.
if rg -q 'bindings\.lua|hypr/|config\.d/' run.sh scripts/fetch-engine.sh scripts/write-desktop-entry.sh; then
  fail 'run.sh or an installer references compositor bindings'
fi

echo 'Bind: README names i3 shell toggle, no install write PASS'
