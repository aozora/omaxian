#!/usr/bin/env bash
# One-shot apt upgradable count (for defpoll).
set -euo pipefail

count="$(apt list --upgradable 2>/dev/null | grep -c / || true)"
if (( count > 0 )); then
	echo " ${count}"
else
	echo " None"
fi
