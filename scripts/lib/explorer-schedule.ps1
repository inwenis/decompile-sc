# Pure helpers for the nightly exploratory-agent scheduling (task 109): the
# schtasks argument construction, the run-dir retention decision, the
# quiet-vs-report notification branch, and the one-run-per-UTC-day cost
# guard. No Start-Process/schtasks.exe/Remove-Item/Get-ChildItem here -- that
# live glue stays in scripts/register-nightly-explorer.ps1,
# scripts/unregister-nightly-explorer.ps1 and scripts/run-explorer-nightly.ps1
# (same pure/live split scripts/lib/explorer-args.ps1 documents for the
# harness itself, and scripts/lib/watchdog-arming.ps1 documents for task 100).

function Get-ExplorerScheduleCommandLine {
    # The single command-line string schtasks /TR takes. Built here instead
    # of string-interpolated at the call site so the quoting (both the pwsh
    # path and the script path can contain spaces -- "Program Files") is
    # unit-testable rather than only provable by actually registering a task.
    param(
        [Parameter(Mandatory)][string]$PwshPath,
        [Parameter(Mandatory)][string]$ScriptPath
    )
    return '"{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}"' -f $PwshPath, $ScriptPath
}

function Get-ExplorerScheduleRegisterArgs {
    # /F makes registration idempotent -- re-running register-nightly-explorer.ps1
    # updates the existing task instead of erroring. /RL LIMITED: standard-user
    # rights, never elevated, for a bug-finding probe.
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$CommandLine,
        [Parameter(Mandatory)][string]$StartTime
    )
    return @('/Create', '/TN', $TaskName, '/TR', $CommandLine, '/SC', 'DAILY', '/ST', $StartTime, '/RL', 'LIMITED', '/F')
}

function Get-ExplorerScheduleUnregisterArgs {
    param([Parameter(Mandatory)][string]$TaskName)
    return @('/Delete', '/TN', $TaskName, '/F')
}

function Get-PrunableExplorerRunDirs {
    # Keep-last-N by name. Run dirs are named <UTC yyyyMMdd-HHmmss>
    # (run-explorer.ps1) -- fixed width, so a plain string sort is also a
    # chronological sort. Anything not matching that shape is left alone: a
    # stray file or a differently-named manual run dir is not this
    # function's business and never gets swept.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$RunDirNames,
        [Parameter(Mandatory)][int]$KeepCount
    )
    $stamped = @($RunDirNames | Where-Object { $_ -match '^\d{8}-\d{6}$' } | Sort-Object -Descending)
    if ($stamped.Count -le $KeepCount) { return @() }
    return @($stamped | Select-Object -Skip $KeepCount)
}

function Test-ExplorerShouldNotify {
    # Findings loop (task 109): run-explorer.ps1 itself always messages the
    # conductor unless given -NoMessage -- fine for an interactive run, wrong
    # for something that fires every night. This is the nightly-only "only
    # when it matters" gate: quiet on a clean run, a message the moment
    # anything is flagged.
    param([Parameter(Mandatory)][int]$FlagCount)
    return $FlagCount -gt 0
}

function Test-ExplorerNightlyRunAllowed {
    # One run per night maximum (task 109, COST IS THE RISK): allowed unless
    # a run already happened on this same UTC calendar day. LastRunDateUtc is
    # deliberately untyped (not [Nullable[DateTime]]): PowerShell boxes a
    # non-null Nullable<DateTime> parameter as a plain boxed DateTime, so a
    # later `.Value` on it silently returns $null instead of erroring --
    # caught by the "same day" test returning the wrong answer.
    param(
        [AllowNull()]$LastRunDateUtc,
        [Parameter(Mandatory)][DateTime]$NowUtc
    )
    if ($null -eq $LastRunDateUtc) { return $true }
    return ([DateTime]$LastRunDateUtc).Date -lt $NowUtc.Date
}
