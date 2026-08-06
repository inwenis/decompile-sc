# Baseline store + history log file IO for scripts/run-mutation-check.ps1.
# The baseline is a single JSON file holding the last ACCEPTED (held or
# improved) score summary -- it is overwritten only when the run does not
# regress. The history log is append-only, one compact JSON line per run
# regardless of outcome, so the run-to-run record is small and readable
# (task 110's Retention requirement) without needing a pruning policy: at
# one run/week it is ~50 lines a year.

function Get-MutationBaseline {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Set-MutationBaseline {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Summary)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    ($Summary | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $Path -Encoding utf8
}

function Add-MutationHistoryLine {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Entry)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $line = $Entry | ConvertTo-Json -Depth 10 -Compress
    Add-Content -LiteralPath $Path -Value $line
}
