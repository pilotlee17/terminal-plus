#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v tmux >/dev/null || { echo "Install tmux first: brew install tmux" >&2; exit 1; }
swift test
python3 scripts/smoke-sessions.py
