#!/usr/bin/env bash
# Build and install the modded game under C:\decompile-sc-data\sc-deploy with its desktop shortcuts; logic in deploy.ps1.
set -euo pipefail
cd "$(dirname "$0")"
if [ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]; then
  echo "deploy: linked worktree, merge first and deploy from the main checkout" >&2
  exit 1
fi
exec pwsh -NoProfile -File ./deploy.ps1 "$@"
