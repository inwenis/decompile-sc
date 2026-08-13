#Requires -Version 7
<#
Pester cases for prune-worktrees (task 069, issue #96).

WHY THESE EXIST. `git worktree remove --force` deregisters the worktree and then
deletes the directory; a delete that failed (a lingering handle) left a directory no
later `git worktree list` walk could surface, and the script reported
`nothing prunable` over six directories still on disk -- four of them 0 MB. The false
report is the defect: the sweep below puts stranded directories back in the script's
scope, and the integration case pins that a strand is FOUND, REMOVED, and never again
covered by a `nothing prunable` line. It fails against the pre-069 script by
construction (no sweep existed; the strand was invisible to it).
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '../scripts/lib/prune-worktrees.ps1')
    $script:pruneScript = (Resolve-Path (Join-Path $PSScriptRoot '../scripts/prune-worktrees.ps1')).Path
}

Describe 'Get-StrandedWorktreeTaskIds' {

    It 'finds a task dir on disk that git no longer registers (the issue #96 strand)' {
        Get-StrandedWorktreeTaskIds -DiskDirNames @('repo', 'repo-task055', 'repo-task061') `
            -RegisteredTaskIds @('061') -RepoPath 'C:/git/repo' |
            Should -Be @('055')
    }

    It 'returns nothing when every task dir is registered' {
        Get-StrandedWorktreeTaskIds -DiskDirNames @('repo', 'repo-task061') `
            -RegisteredTaskIds @('061') -RepoPath 'C:/git/repo' |
            Should -BeNullOrEmpty
    }

    It 'never matches the main repo dir, other repos, or non-convention names' {
        Get-StrandedWorktreeTaskIds -DiskDirNames @('repo', 'repo-old', 'other-task055', 'repo-task55', 'repo-task0555') `
            -RegisteredTaskIds @() -RepoPath 'C:/git/repo' |
            Should -BeNullOrEmpty
    }

    It 'handles empty disk listings' {
        Get-StrandedWorktreeTaskIds -DiskDirNames @() -RegisteredTaskIds @() -RepoPath 'C:/git/repo' |
            Should -BeNullOrEmpty
    }
}

Describe 'prune-worktrees.ps1 against a fixture repo' {

    BeforeEach {
        $script:root = Join-Path ([IO.Path]::GetTempPath()) "prune-tests-$([guid]::NewGuid().ToString('N'))"
        $script:repo = Join-Path $script:root 'repo'
        New-Item -ItemType Directory -Path (Join-Path $script:repo 'work/tasks') -Force | Out-Null
        git -C $script:repo init -q 2>&1 | Out-Null
        git -C $script:repo -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>&1 | Out-Null
    }
    AfterEach {
        if ($script:root -and (Test-Path -LiteralPath $script:root)) {
            Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'finds and removes a STRANDED merged-task dir, and does not report "nothing prunable" over it' {
        # The exact post-incident shape: dir on disk, NOT in git worktree list,
        # task file merged-stamped.
        $strand = Join-Path $script:root 'repo-task055'
        New-Item -ItemType Directory -Path $strand | Out-Null
        Set-Content -LiteralPath (Join-Path $script:repo 'work/tasks/055-old-thing.md') -Value @'
# Task 055 - old thing

agent: 055
pr: https://github.com/x/y/pull/9
merged: 2026-08-13
'@
        $out = & $script:pruneScript -Repo $script:repo -Force 6>&1 | ForEach-Object { "$_" }
        ($out -join "`n") | Should -Not -Match 'nothing prunable'
        ($out -join "`n") | Should -Match 'STRANDED'
        Test-Path -LiteralPath $strand | Should -BeFalse
    }

    It 'names an UNMERGED stranded dir honestly and never touches it' {
        $strand = Join-Path $script:root 'repo-task056'
        New-Item -ItemType Directory -Path $strand | Out-Null
        Set-Content -LiteralPath (Join-Path $script:repo 'work/tasks/056-open-thing.md') -Value @'
# Task 056 - open thing

agent: 056
pr: -
'@
        $out = & $script:pruneScript -Repo $script:repo -Force 6>&1 | ForEach-Object { "$_" }
        ($out -join "`n") | Should -Match 'no merged: stamp'
        ($out -join "`n") | Should -Match 'not touching'
        Test-Path -LiteralPath $strand | Should -BeTrue
    }

    It 'lists a stranded dir on the DRY RUN without removing it' {
        $strand = Join-Path $script:root 'repo-task057'
        New-Item -ItemType Directory -Path $strand | Out-Null
        Set-Content -LiteralPath (Join-Path $script:repo 'work/tasks/057-done-thing.md') -Value @'
# Task 057 - done thing

agent: 057
pr: https://github.com/x/y/pull/9
merged: 2026-08-13
'@
        $out = & $script:pruneScript -Repo $script:repo 6>&1 | ForEach-Object { "$_" }
        ($out -join "`n") | Should -Match 'STRANDED'
        ($out -join "`n") | Should -Match 'DRY RUN'
        Test-Path -LiteralPath $strand | Should -BeTrue
    }

    It 'keeps a REGISTERED worktree registered when its directory cannot be removed, and says who to blame is unknown-but-local' {
        # Registered worktree of a merged task, with an open handle inside it so the
        # removal fails: the fix's ordering guarantee is that the worktree must STAY
        # in `git worktree list` (the old order deregistered first and stranded it).
        $wt = Join-Path $script:root 'repo-task058'
        git -C $script:repo worktree add -q $wt 2>&1 | Out-Null
        Set-Content -LiteralPath (Join-Path $script:repo 'work/tasks/058-held-thing.md') -Value @'
# Task 058 - held thing

agent: 058
pr: https://github.com/x/y/pull/9
merged: 2026-08-13
'@
        $holder = [IO.File]::Open((Join-Path $wt 'held.bin'), [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            # The held file makes the worktree dirty (untracked) too -- bypass that
            # separate guard by committing it... simpler: hold the .git FILE itself,
            # which is invisible to `git status` but blocks the directory delete.
            $holder.Close()
            Remove-Item -LiteralPath (Join-Path $wt 'held.bin') -Force
            $holder = [IO.File]::Open((Join-Path $wt '.git'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)

            $out = & $script:pruneScript -Repo $script:repo -Force -WarningAction SilentlyContinue 6>&1 3>&1 2>&1 |
                ForEach-Object { "$_" }
            ($out -join "`n") | Should -Match 'could not remove'
            ($out -join "`n") | Should -Match 'REGISTERED'
            # The ordering guarantee itself:
            $list = (git -C $script:repo worktree list --porcelain) -join "`n"
            $list | Should -Match ([regex]::Escape('repo-task058'))
        }
        finally { $holder.Close() }
    }
}
