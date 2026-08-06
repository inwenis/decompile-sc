# Live CIM/file glue shared by check-conductors.ps1 and watchdog-daemon.ps1
# (task 100). Extracted out of check-conductors.ps1 (task 089) so the
# session-arming daemon does not duplicate the process-reading logic --
# both callers dot-source this and call Get-LiveConductorReport. The pure
# verdict logic it delegates to stays in conductor-watchdog.ps1; this file
# is the thin, NOT Pester-tested half (same split scripts/lib/agent-proc.ps1
# documents for live process code).

. (Join-Path $PSScriptRoot 'process-cwd.ps1')

function Get-LiveConductorReport {
    param(
        [Parameter(Mandatory)][string]$Repo,
        # The conductor's canonical home, for the cwd-shape exclusion (task
        # 100) -- deliberately distinct from -Repo, which is only where THIS
        # tool reads/writes its own data and may itself be a worktree (e.g.
        # a live smoke test). Defaults match config/conductor-sessionstart.ps1's
        # own CONDUCTOR_REPO_ROOT convention for "what is the real main checkout".
        [string]$MainCheckoutRoot = $(if ($env:CONDUCTOR_REPO_ROOT) { $env:CONDUCTOR_REPO_ROOT } else { 'C:\git\decompile-sc' }),
        [string]$SessionFile = $(if ($env:CONDUCTOR_SESSION_FILE) { $env:CONDUCTOR_SESSION_FILE } else { $null }),
        [string]$StatusFile = $(if ($env:CONDUCTOR_STATUS_FILE) { $env:CONDUCTOR_STATUS_FILE } else { $null })
    )

    $dataRoot = Get-DataRoot -RepoRoot $Repo
    if (-not $SessionFile) { $SessionFile = Join-Path $dataRoot 'scratch/conductor-session-id' }
    if (-not $StatusFile) { $StatusFile = Join-Path $dataRoot 'messages/conductor/status.json' }

    $procs = @(Get-CimInstance Win32_Process -Filter "Name='claude.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object {
            [PSCustomObject]@{
                Pid              = [int]$_.ProcessId
                StartTime        = $_.CreationDate
                CommandLine      = $_.CommandLine
                WorkingDirectory = Get-ProcessWorkingDirectory -ProcessId $_.ProcessId
            }
        })
    $candidates = Get-ConductorShapedProcesses -Processes $procs -MainCheckoutRoot $MainCheckoutRoot

    $registeredSessionId = $null
    $registrationLastWriteUtc = $null
    if (Test-Path -LiteralPath $SessionFile) {
        $registeredSessionId = (Get-Content -LiteralPath $SessionFile -Raw -ErrorAction SilentlyContinue).Trim()
        $registrationLastWriteUtc = (Get-Item -LiteralPath $SessionFile).LastWriteTimeUtc
    }

    $statusUpdatedAtUtc = $null
    if (Test-Path -LiteralPath $StatusFile) {
        try {
            $status = Get-Content -LiteralPath $StatusFile -Raw | ConvertFrom-Json
            if ($status.updatedAt) { $statusUpdatedAtUtc = ConvertFrom-IsoUtc -Value $status.updatedAt }
        }
        catch {}
    }

    $report = Get-ConductorWatchdogReport -Candidates $candidates `
        -RegisteredSessionId $registeredSessionId `
        -RegistrationLastWriteUtc $registrationLastWriteUtc `
        -StatusUpdatedAtUtc $statusUpdatedAtUtc `
        -NowUtc ([DateTime]::UtcNow)

    # Change-signature (same shape check-conductors.ps1 -Watch already used
    # inline to print only on change) hoisted here so every caller that wants
    # "did anything change since last poll" gets the identical value instead
    # of recomputing it.
    $rowSig = ($report.Rows | ForEach-Object { "$($_.Pid)@$($_.StartTime.Ticks)" }) -join ','
    $signature = "$($report.Count)|$rowSig|$($report.RegisteredSessionId)"
    $report | Add-Member -NotePropertyName Signature -NotePropertyValue $signature

    return $report
}
