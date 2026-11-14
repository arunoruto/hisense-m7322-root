#!/usr/bin/env bash
# Compatibility entry point; port is now explicit and bootargs come from the TV.
set -eu
exec python3 "$(dirname "$0")/serial-console.py" --maintenance "$@"
