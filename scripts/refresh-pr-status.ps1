#Requires -Version 7
<#
.SYNOPSIS
Refresh scratch/pr-status.json from GitHub for every task file with a pr: URL.

.DESCRIPTION
Architecture constraint (task 036 / specs.md §5): the Agent Console adapter
stays filesystem-only and must never shell out to gh. This script is the
side that does -- it walks work/tasks/*.md, calls `gh pr view` for every task
carrying a `pr:` URL in its Status section, and writes one snapshot file
(work/scratch/pr-status.json) the adapter just reads. Idempotent and safe to run
on a timer or once per conductor loop; each run overwrites the file whole.

Written shape: one `fetchedAt` stamp for the whole run, plus one entry per
task id --
  { "fetchedAt": "...", "036": { "number": 31, "state": "open", "mergeable": true, "url": "...", "createdAt": "..." } }

.EXAMPLE
./scripts/refresh-pr-status.ps1
#>
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/pr-status.ps1')
. (Join-Path $PSScriptRoot 'lib/data-root.ps1')

$dataRoot = Get-DataRoot -RepoRoot $RepoRoot
$tasksDir = Join-Path $dataRoot 'tasks'
$taskFiles = Get-ChildItem -Path $tasksDir -Filter '*.md' |
    Where-Object { $_.Name -match '^\d+-.+\.md$' }

$refs = @(
    foreach ($file in $taskFiles) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        Get-TaskPrRef -Content $content
    }
) | Where-Object { $_ }

$result = [ordered]@{ fetchedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }

foreach ($ref in $refs) {
    $ghJson = gh pr view $ref.Url --json number,state,mergeable,url,createdAt 2>$null
    if (-not $ghJson) {
        Write-Warning "gh pr view failed for $($ref.Url) (task $($ref.TaskId)) -- skipping"
        continue
    }
    $pr = $ghJson | ConvertFrom-Json
    $result[$ref.TaskId] = [ordered]@{
        number    = $pr.number
        state     = ConvertTo-PrState $pr.state
        mergeable = ConvertTo-MergeableBool $pr.mergeable
        url       = $pr.url
        createdAt = $pr.createdAt
    }
}

$scratchDir = Join-Path $dataRoot 'scratch'
if (-not (Test-Path -LiteralPath $scratchDir)) {
    New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null
}
$outPath = Join-Path $scratchDir 'pr-status.json'
($result | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $outPath -Encoding utf8NoBOM

Write-Output ($outPath -replace '\\', '/')
