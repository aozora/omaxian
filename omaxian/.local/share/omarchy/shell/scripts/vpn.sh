#!/usr/bin/env bash
# VPN indicator (WireGuard / NM WireGuard / NymVPN tun).
set -euo pipefail

wireguard_up() {
	ip link show type wireguard 2>/dev/null | grep -q 'LOWER_UP'
}

nm_wireguard_up() {
	command -v nmcli >/dev/null 2>&1 \
		&& nmcli -t -f TYPE,STATE connection show --active 2>/dev/null \
			| grep -q '^wireguard:activated'
}

nymvpn_up() {
	pgrep -x nym-vpnd >/dev/null 2>&1 \
		&& ip link show type tun 2>/dev/null | grep -q 'LOWER_UP'
}

if wireguard_up || nm_wireguard_up || nymvpn_up; then
	echo "󰕥"
else
	echo ""
fi
