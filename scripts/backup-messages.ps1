#Requires -Version 7
<#
.SYNOPSIS
Snapshot the private messages/ tree into its nested git repo and push.

.DESCRIPTION
work/messages/ is gitignored by the product repo but is itself a git repo pushed to
the private inwenis/conductor-messages remote. Before 2026-07-17 it had ONE
manual commit from 2026-07-12 — when a worker demo wiped messages/user/, five
days of messages had no backup (data-loss incident). This script makes the
backup a mechanism instead of a memory (ground rule 1): stage everything,
commit if anything changed, push. Wired into close-task.ps1 (runs several
times a day) and the conductor SessionStart hook.

Exit code 0 always on the no-change path; throws on git failures.
#>
param(
    [string]$MessagesDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'work/messages')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path (Join-Path $MessagesDir '.git'))) {
    throw "backup-messages: $MessagesDir is not a git repo -- nothing to back up into."
}

git -C $MessagesDir add -A
$staged = git -C $MessagesDir status --porcelain
if (-not $staged) {
    Write-Host 'backup-messages: no changes'
    exit 0
}

$stamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
git -C $MessagesDir commit -m "messages snapshot $stamp" --quiet
git -C $MessagesDir push origin HEAD --quiet
Write-Host "backup-messages: committed + pushed snapshot $stamp"
