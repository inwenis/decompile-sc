#Requires -Version 7
<#
Pester cases for tools/sc-python.ps1.

Worktrees are cut without a .venv, and `python` on PATH here has no richchk: an
unguarded fallback to it generates no map and leaves drive-game blaming the wrong
thing. The contract pinned here: a worktree with no .venv of its own resolves the
MAIN checkout's .venv, and an interpreter that cannot import the required module is
rejected with a recorded reason, never used silently.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '../tools/sc-python.ps1')

    $script:root = Join-Path ([IO.Path]::GetTempPath()) "sc-python-tests-$([guid]::NewGuid().ToString('N'))"
    $script:main = Join-Path $script:root 'repo'
    $script:wt = Join-Path $script:root 'repo-task001'
    New-Item -ItemType Directory -Path $script:main | Out-Null

    # A tiny real repo with one commit, so `git worktree add` works.
    git -C $script:main init -q 2>&1 | Out-Null
    git -C $script:main -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>&1 | Out-Null
    git -C $script:main worktree add -q $script:wt 2>&1 | Out-Null

    # The main checkout's "venv": a placeholder file where python.exe would be. A
    # candidate is only Test-Path'd unless -RequireModule is given, so a placeholder is
    # enough to pin which path resolution picks.
    $script:mainVenvPy = Join-Path $script:main '.venv/Scripts/python.exe'
    New-Item -ItemType Directory -Path (Split-Path $script:mainVenvPy -Parent) -Force | Out-Null
    Set-Content -LiteralPath $script:mainVenvPy -Value 'placeholder'
}

AfterAll {
    if ($script:root -and (Test-Path -LiteralPath $script:root)) {
        git -C $script:main worktree remove --force $script:wt 2>&1 | Out-Null
        Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Resolve-ScPython closes the worktree .venv gap' {

    It 'resolves the MAIN checkout .venv from a worktree that has none (the issue #97 gap)' {
        # Discriminating by construction: a resolver that searches only the calling
        # checkout cannot pass this, because the worktree holds no .venv of its own.
        $r = Resolve-ScPython -RepoRoot $script:wt
        $r.Path | Should -Be $script:mainVenvPy
        $r.Source | Should -Match 'main checkout'
    }

    It 'prefers the calling checkout own .venv when one exists' {
        $wtVenvPy = Join-Path $script:wt '.venv/Scripts/python.exe'
        New-Item -ItemType Directory -Path (Split-Path $wtVenvPy -Parent) -Force | Out-Null
        Set-Content -LiteralPath $wtVenvPy -Value 'placeholder'
        try {
            $r = Resolve-ScPython -RepoRoot $script:wt
            $r.Path | Should -Be $wtVenvPy
            $r.Source | Should -Match "this checkout's"
        }
        finally { Remove-Item -LiteralPath (Join-Path $script:wt '.venv') -Recurse -Force }
    }

    It 'records every rejected candidate with its reason instead of silently using one' {
        # A module name no interpreter can satisfy, so every candidate must be rejected
        # and named in Probed rather than one being used anyway.
        $r = Resolve-ScPython -RepoRoot $script:wt -RequireModule 'no_such_module_task069_zzz'
        $r.Path | Should -BeNullOrEmpty
        @($r.Probed).Count | Should -BeGreaterThan 0
        ($r.Probed -join "`n") | Should -Match 'cannot import no_such_module_task069_zzz|no interpreter'
    }

    It 'still resolves PATH python for a checkout with no venv anywhere (the CI runner shape)' {
        # With neither checkout holding a .venv, PATH python is the last candidate left.
        if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'no python on PATH on this machine'
        }
        Remove-Item -LiteralPath (Join-Path $script:main '.venv') -Recurse -Force
        try {
            $r = Resolve-ScPython -RepoRoot $script:wt
            $r.Path | Should -Not -BeNullOrEmpty
            $r.Source | Should -Be 'python on PATH'
        }
        finally {
            New-Item -ItemType Directory -Path (Split-Path $script:mainVenvPy -Parent) -Force | Out-Null
            Set-Content -LiteralPath $script:mainVenvPy -Value 'placeholder'
        }
    }
}
