#!/bin/bash
# Compatibility shim — real script lives in scripts/install.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/install.sh" "$@"
