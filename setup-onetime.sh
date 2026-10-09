#!/usr/bin/env bash
# Install the pinned toolchain, cnc-ddraw and Pester 5, plus the game working copy given -StarCraftDir; logic in setup-onetime.ps1.
set -euo pipefail
cd "$(dirname "$0")"
exec pwsh -NoProfile -File ./setup-onetime.ps1 "$@"
