#!/usr/bin/env bash
# Build and install the modded game under C:\decompile-sc-data\sc-deploy with its desktop shortcuts; logic in deploy.ps1.
set -euo pipefail
cd "$(dirname "$0")"
exec pwsh -NoProfile -File ./deploy.ps1 "$@"
