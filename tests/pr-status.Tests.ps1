#Requires -Version 7
<#
Pester cases for the merged-PR skip in scripts/refresh-pr-status.ps1 and its
lib/pr-status.ps1 helper Test-PrRefreshNeeded.

WHY THIS EXISTS. conductor-sessionstart.ps1 runs refresh-pr-status.ps1, which
called `gh pr view` once per task carrying a pr: URL -- finished tasks
included -- so session start grew with board history: measured 2026-08-16,
32s of the 40.1s SessionStart hook was this loop, and the user's first
/ command in a fresh session waited the whole 40s. A merged PR is immutable
on GitHub, so its cached snapshot entry is reused instead of re-fetched;
open PRs stay live and closed PRs can reopen, so both are still fetched.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '../scripts/lib/pr-status.ps1')
}

Describe 'Test-PrRefreshNeeded' {
    It 'fetches when there is no cached entry' {
        Test-PrRefreshNeeded -CachedEntry $null | Should -BeTrue
    }
    It 'fetches an open PR (state can still change)' {
        Test-PrRefreshNeeded -CachedEntry ([pscustomobject]@{ state = 'open' }) | Should -BeTrue
    }
    It 'fetches a closed PR (it can reopen)' {
        Test-PrRefreshNeeded -CachedEntry ([pscustomobject]@{ state = 'closed' }) | Should -BeTrue
    }
    It 'skips a merged PR (immutable on GitHub)' {
        Test-PrRefreshNeeded -CachedEntry ([pscustomobject]@{ state = 'merged' }) | Should -BeFalse
    }
    It 'fetches when the cached entry carries no state' {
        Test-PrRefreshNeeded -CachedEntry ([pscustomobject]@{ number = 5 }) | Should -BeTrue
    }
}

Describe 'refresh-pr-status.ps1 reuses cached merged entries' {

    BeforeAll {
        $script:scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '../scripts/refresh-pr-status.ps1')).Path

        # Stub gh: records every `gh pr view <url> ...` and answers OPEN.
        # global: so the child script's command lookup finds it before gh.exe.
        $global:ghViewCalls = [System.Collections.Generic.List[string]]::new()
        function global:gh {
            if ($args[0] -eq 'pr' -and $args[1] -eq 'view') {
                $global:ghViewCalls.Add($args[2])
                return '{"number":77,"state":"OPEN","mergeable":"MERGEABLE","url":"' + $args[2] + '","createdAt":"2026-08-01T00:00:00Z"}'
            }
            throw "unexpected gh invocation: $args"
        }
    }

    AfterAll {
        Remove-Item function:global:gh -ErrorAction SilentlyContinue
        Remove-Variable -Name ghViewCalls -Scope Global -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $global:ghViewCalls.Clear()
        $script:root = Join-Path ([IO.Path]::GetTempPath()) "pr-status-test-$([guid]::NewGuid().ToString('N'))"
        $tasks = Join-Path $script:root 'work/tasks'
        $scratch = Join-Path $script:root 'work/scratch'
        New-Item -ItemType Directory -Path $tasks, $scratch -Force | Out-Null

        # Em-dash heading + pr: line is the exact shape Get-TaskPrRef parses.
        Set-Content (Join-Path $tasks '036-done-long-ago.md') -Value "# Task 036 — done long ago`npr: https://github.com/x/y/pull/31`n"
        Set-Content (Join-Path $tasks '041-still-open.md')    -Value "# Task 041 — still open`npr: https://github.com/x/y/pull/44`n"
        Set-Content (Join-Path $tasks '050-never-cached.md')  -Value "# Task 050 — never cached`npr: https://github.com/x/y/pull/55`n"

        @'
{
  "fetchedAt": "2026-08-01T00:00:00Z",
  "036": { "number": 31, "state": "merged", "mergeable": true, "url": "https://github.com/x/y/pull/31", "createdAt": "2026-07-01T00:00:00Z" },
  "041": { "number": 44, "state": "open",   "mergeable": true, "url": "https://github.com/x/y/pull/44", "createdAt": "2026-07-10T00:00:00Z" }
}
'@ | Set-Content (Join-Path $scratch 'pr-status.json')
    }

    AfterEach {
        Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'calls gh only for the non-merged tasks' {
        & $script:scriptPath -RepoRoot $script:root | Out-Null
        $global:ghViewCalls | Should -HaveCount 2
        $global:ghViewCalls | Should -Not -Contain 'https://github.com/x/y/pull/31'
    }

    It 'carries the merged entry forward unchanged and still fetches the rest' {
        & $script:scriptPath -RepoRoot $script:root | Out-Null
        # -DateKind String: assert the VERBATIM file text, not a [datetime] roundtrip
        $written = Get-Content (Join-Path $script:root 'work/scratch/pr-status.json') -Raw | ConvertFrom-Json -DateKind String
        $written.'036'.state | Should -Be 'merged'
        $written.'036'.number | Should -Be 31
        $written.'036'.createdAt | Should -Be '2026-07-01T00:00:00Z'
        $written.'041'.number | Should -Be 77   # refreshed from the stub, not the cache
        $written.'050'.state | Should -Be 'open'
    }

    It 'fetches everything when no snapshot exists yet' {
        Remove-Item (Join-Path $script:root 'work/scratch/pr-status.json')
        & $script:scriptPath -RepoRoot $script:root | Out-Null
        $global:ghViewCalls | Should -HaveCount 3
    }
}
