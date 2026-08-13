# Pure/testable helpers for prune-worktrees.ps1 -- the merged-task worktree
# backlog cleanup (task 063, report 055 PROPOSAL 5). No git/filesystem work
# lives here -- those side effects stay in scripts/prune-worktrees.ps1 so this
# file can be dot-sourced straight into Pester and exercised on strings and
# hashtables. See tests/prune-worktrees.Tests.ps1.
#
# Worktree listing convention aligned with the user's existing
# C:/git/dotfiles/powershell/profile.shared.ps1 Get-GitWorktrees (user
# relay, task 063): --porcelain, not the human-readable table. Porcelain is
# git's only documented-stable machine format; the aligned-columns table has
# no format guarantee across git versions.

function ConvertFrom-WorktreeListPorcelain {
    # Parses the FULL output of `git worktree list --porcelain`: stanzas
    # separated by a blank line, each stanza a few `key value` lines
    # (worktree/HEAD/branch, or `bare`/`detached` with no branch). Mirrors
    # Get-GitWorktrees' stanza-split approach. Skips the bare-repo pseudo-entry
    # (a lone `bare` line, no worktree path questions apply to it) and any
    # detached-HEAD stanza (no `branch` line -- never a taskNNN worktree).
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $stanzas = [regex]::Split($Text, '(?:\r?\n){2,}') | Where-Object { $_.Trim() }
    $result = foreach ($s in $stanzas) {
        if ($s -match '(?m)^bare\r?$') { continue }
        # [^\r\n]+ (not .+) so a CRLF-checked-out file never leaves a trailing
        # \r inside the capture -- (?m)$ matches just before \n, not before \r,
        # so a greedy .+ swallows it (CI red on PR #59: 'C:/git/conductor' vs
        # 'C:/git/conductor<CR>').
        $pathMatch = [regex]::Match($s, '(?m)^worktree ([^\r\n]+)')
        $branchMatch = [regex]::Match($s, '(?m)^branch refs/heads/([^\r\n]+)')
        if (-not $pathMatch.Success -or -not $branchMatch.Success) { continue }
        [pscustomobject]@{
            Path   = $pathMatch.Groups[1].Value -replace '\\', '/'
            Branch = $branchMatch.Groups[1].Value
        }
    }
    return @($result)
}

function Get-TaskIdFromWorktreePath {
    # "<repoPath>-task<NNN>" -> "<NNN>". $null for the main checkout itself
    # or any worktree that doesn't follow the taskNNN convention (AGENTS.md
    # § Conventions) -- never guess a task id for a path that doesn't fit it.
    param(
        [Parameter(Mandatory)][string]$WorktreePath,
        [Parameter(Mandatory)][string]$RepoPath
    )
    $wt = ($WorktreePath -replace '\\', '/').TrimEnd('/')
    $repo = ($RepoPath -replace '\\', '/').TrimEnd('/')
    $m = [regex]::Match($wt, [regex]::Escape("$repo-task") + '(\d{3})$')
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value
}

function Get-StrandedWorktreeTaskIds {
    # Task-worktree directories that exist ON DISK but that git no longer
    # registers (issue #96, task 069). The old removal order -- deregister,
    # then delete -- could fail the delete AFTER the deregistration, leaving a
    # directory no later `git worktree list` walk would ever surface; the
    # script then printed `nothing prunable` over six directories still on
    # disk. Pure set logic on directory LEAF names so Pester can drive it
    # without a filesystem: the caller lists the repo's parent directory and
    # passes the leaf names in.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$DiskDirNames,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$RegisteredTaskIds,
        [Parameter(Mandatory)][string]$RepoPath
    )
    $repoLeaf = Split-Path (($RepoPath -replace '\\', '/').TrimEnd('/')) -Leaf
    $registered = [Collections.Generic.HashSet[string]]::new()
    foreach ($id in $RegisteredTaskIds) { [void]$registered.Add($id) }
    $ids = foreach ($name in $DiskDirNames) {
        $m = [regex]::Match($name, '^' + [regex]::Escape("$repoLeaf-task") + '(\d{3})$')
        if (-not $m.Success) { continue }
        if ($registered.Contains($m.Groups[1].Value)) { continue }
        $m.Groups[1].Value
    }
    return @($ids | Sort-Object)
}

function Get-PrunableWorktreeIds {
    # Given every registered worktree's task id and a lookup of which task
    # ids have a merged: stamp (Test-HasMergedStamp per task, computed by the
    # caller from real file content), return only the ids that are safe
    # prune candidates. Pure set logic -- memory lesson: never prune an open
    # task's worktree, so an id absent from MergedById or mapped to $false
    # never comes back here.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$WorktreeTaskIds,
        [Parameter(Mandatory)][hashtable]$MergedById
    )
    return @($WorktreeTaskIds | Where-Object { $MergedById.ContainsKey($_) -and $MergedById[$_] })
}
