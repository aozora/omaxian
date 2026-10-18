#!/bin/bash
# Compatibility shim — real script lives in scripts/deploy.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/deploy.sh" "$@"
