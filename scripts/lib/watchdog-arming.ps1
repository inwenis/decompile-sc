# Pure decision logic for arming/retiring the duplicate-conductor watchdog
# every session (task 100 -- USER ORDER 2026-07-20: "i want the conductor to
# run this script while we work here for the next 2 weeks. if we don't
# detect double conductors after that we will retire the script."). Ground
# rule 1 (automation over memory): a conductor's in-session promise dies
# with the session, so arming and retirement both have to be mechanized
# instead of remembered.
#
# Live glue (lock-file reads, Get-Process, spawning the daemon) stays in
# scripts/arm-watchdog.ps1 / scripts/watchdog-daemon.ps1 -- same split
# scripts/lib/agent-proc.ps1 documents for live process code that isn't
# unit-tested. Everything in this file takes plain values in and returns
# plain values out.

# Hardcoded per the task: retirement is part of the mechanism, not a note
# in someone's head.
$script:WatchdogRetireOnUtc = [DateTime]::new(2026, 8, 3, 0, 0, 0, [DateTimeKind]::Utc)

function Get-WatchdogRetireOnUtc {
    return $script:WatchdogRetireOnUtc
}

function Test-WatchdogRetirementDue {
    # On/after the review date -> due. Strictly a date compare so "on" the
    # day (any time after midnight UTC) counts, matching "on or after it" in
    # the task.
    param([Parameter(Mandatory)][DateTime]$NowUtc, [Parameter(Mandatory)][DateTime]$RetireOnUtc)
    return $NowUtc -ge $RetireOnUtc
}

function Get-DuplicateDetectionCount {
    # One log line = one detection (the daemon writes on the duplicate-state
    # rising edge, not every poll tick -- see watchdog-daemon.ps1). Counting
    # non-blank lines is all the "summary" needs to be.
    param([AllowNull()][AllowEmptyCollection()][string[]]$LogLines)
    if (-not $LogLines) { return 0 }
    return @($LogLines | Where-Object { $_ -and $_.Trim() }).Count
}

function Test-WatchdogShouldSpawn {
    # Single-instance decision: don't spawn a second daemon while a genuine
    # one is already running. Facts are precomputed by the caller (lock file
    # existence, whether its recorded pid is alive, whether that pid's own
    # command line actually looks like our daemon -- guards against a reused
    # pid coincidentally belonging to an unrelated process).
    param(
        [Parameter(Mandatory)][bool]$LockExists,
        [Parameter(Mandatory)][bool]$LockPidAlive,
        [Parameter(Mandatory)][bool]$LockIsDaemonProcess
    )
    if (-not $LockExists) { return $true }
    if (-not $LockPidAlive) { return $true }
    if (-not $LockIsDaemonProcess) { return $true }
    return $false
}

function Get-WatchdogBoardLines {
    # SessionStart board lines (task 100 acceptance criteria 4): armed state
    # every session, plus a retire-or-keep prompt carrying the evidence once
    # the review date arrives. Never auto-deletes anything -- the user
    # decides; this only ever asks.
    param(
        [Parameter(Mandatory)][DateTime]$NowUtc,
        [Parameter(Mandatory)][DateTime]$RetireOnUtc,
        [Parameter(Mandatory)][int]$DetectionCount,
        [Parameter(Mandatory)][bool]$DaemonArmed,
        [Parameter(Mandatory)][string]$LogPath
    )
    $lines = @()
    $lines += if ($DaemonArmed) {
        "watchdog: armed (duplicate-conductor daemon running; $DetectionCount detection(s) logged so far)"
    } else {
        "watchdog: NOT ARMED -- spawn failed, check work/scratch/arm-watchdog.log"
    }
    if (Test-WatchdogRetirementDue -NowUtc $NowUtc -RetireOnUtc $RetireOnUtc) {
        $lines += "WATCHDOG RETIREMENT DUE (ran since 2026-07-20 through $($RetireOnUtc.ToString('yyyy-MM-dd'))): " +
            "ask the user whether to retire scripts/check-conductors.ps1. " +
            "Evidence: $DetectionCount duplicate-conductor detection(s) recorded in $LogPath " +
            "(zero is the expected, desired answer). Do not delete the script yourself -- the user decides."
    }
    # Unary comma: without it PowerShell unwraps a 1-element array return
    # into a bare scalar string (same bug class as Get-ConductorShapedProcesses
    # in conductor-watchdog.ps1) -- the pre-retirement case is exactly 1 line.
    return , $lines
}
