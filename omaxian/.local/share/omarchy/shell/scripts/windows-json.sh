#!/usr/bin/env bash
# i3 window list as JSON for eww `for` widgets.
set -euo pipefail

i3-msg -t get_tree 2>/dev/null | jq -c '
	[
		.. | objects
		| select(.window? != null and .window != null)
		| select(.window_properties.class != null)
		| {
			id: .id,
			class: .window_properties.class,
			name: (.name // ""),
			output: (.output // "")
		}
	][0:40]
' 2>/dev/null || echo '[]'
