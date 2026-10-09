#!/usr/bin/env bash
# Report the prerequisites and create this checkout's .venv from requirements.txt; logic in setup-worktree.ps1.
set -euo pipefail
cd "$(dirname "$0")"
exec pwsh -NoProfile -File ./setup-worktree.ps1 "$@"
