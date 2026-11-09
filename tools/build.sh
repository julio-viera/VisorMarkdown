#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
python3 tools/app-info.py sync
"$FLUTTER_BIN" build linux --release
