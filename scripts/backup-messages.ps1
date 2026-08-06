#Requires -Version 7
<#
.SYNOPSIS
Commit + push the tracked work/messages/ tree so no message ever sits unpushed.

.DESCRIPTION
DESIGN (this repo, decompile-sc): work/messages/ is TRACKED BY THE MAIN REPO
(see .gitignore: "tasks/, reports/, messages/ stay tracked"). This differs from
the upstream conductor repo, where messages/ was gitignored and lived in its own
nested git repo pushed to a private conductor-messages remote. DO NOT recreate
that wiring here: no nested work/messages/.git, no conductor-messages remote --
that remote belongs to the OTHER live system and pushing this repo's messages
there is cross-repo contamination.

Backup mechanism instead of memory (2026-07-17 data-loss class: a wiped
messages/user/ had a 5-day-stale manual backup): this script commits any
pending work/messages changes on main (pathspec commit -- other staged/unstaged
work is untouched) and pushes main to origin. Wired into close-task.ps1 and the
conductor SessionStart hook.

Exit code 0 on the no-change path; throws on git failures.
#>
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'

$messagesRel = 'work/messages'
if (-not (Test-Path (Join-Path $RepoRoot $messagesRel))) {
    throw "backup-messages: $RepoRoot/$messagesRel does not exist -- nothing to back up."
}

$pending = git -C $RepoRoot status --porcelain -- $messagesRel
if ($LASTEXITCODE -ne 0) { throw "backup-messages: git status failed under $RepoRoot." }

if ($pending) {
    git -C $RepoRoot add -A -- $messagesRel
    if ($LASTEXITCODE -ne 0) { throw 'backup-messages: git add failed.' }
    $stamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    git -C $RepoRoot commit -m "chore(messages): snapshot $stamp" --quiet -- $messagesRel
    if ($LASTEXITCODE -ne 0) { throw 'backup-messages: git commit failed.' }
}

# Push even when nothing new was committed: earlier message commits may still
# be sitting local-only (the exact stale-origin gap this backup exists to close).
$ahead = git -C $RepoRoot rev-list --count '@{u}..HEAD' 2>$null
if ($LASTEXITCODE -ne 0) { $ahead = '1' }  # no upstream info -> just try the push
if (-not $pending -and $ahead -eq '0') {
    Write-Host 'backup-messages: no changes (messages tracked in main repo, all pushed)'
    exit 0
}

git -C $RepoRoot push origin main --quiet
if ($LASTEXITCODE -ne 0) { throw 'backup-messages: git push origin main failed -- messages committed locally but NOT backed up to origin.' }
Write-Host "backup-messages: messages committed + pushed to origin/main$(if ($pending) { " (snapshot)" } else { ' (catch-up push)' })"
