#!/usr/bin/env bash
# Build scplugin.dll + scinject.exe into work/scratch/plugin-build (-Test runs hooktest); logic in build.ps1.
set -euo pipefail
cd "$(dirname "$0")"
exec pwsh -NoProfile -File ./build.ps1 "$@"
