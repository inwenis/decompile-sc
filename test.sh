#!/usr/bin/env bash
# Every check that gates a merge; CI runs this script. Logic in test.ps1.
set -euo pipefail
cd "$(dirname "$0")"
exec pwsh -NoProfile -File ./test.ps1 "$@"
