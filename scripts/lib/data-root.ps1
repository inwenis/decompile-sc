# Single source of truth for the orchestration DATA root (task 068 migration):
# tasks/, messages/, reports/, scratch/ live under <repo>/work/ so code vs
# work-in-progress is obvious at a glance. Root keeps the runnable scripts.
# Every script/hook that used to build paths straight off the repo root for
# these four dirs now resolves this once and uses it instead.

function Get-DataRoot {
    param([Parameter(Mandatory)][string]$RepoRoot)
    return Join-Path $RepoRoot 'work'
}
