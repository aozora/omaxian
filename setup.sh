#!/bin/bash
# Compatibility shim — real script lives in scripts/setup.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/setup.sh" "$@"
