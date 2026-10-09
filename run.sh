#!/usr/bin/env bash
# Play the mod from this checkout in a window, plugin rebuilt when stale, until the game exits; logic in run.ps1.
set -euo pipefail
cd "$(dirname "$0")"
exec pwsh -NoProfile -File ./run.ps1 "$@"
