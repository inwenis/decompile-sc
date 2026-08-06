# Pure decision logic for check-conductors.ps1 (task 089 -- USER REQUEST
# 2026-07-20: "the double conductor ... write a script that we will
# temporarily run that will check if this happens again"). Detection +
# evidence only; never kills anything, never writes state.
#
# Three complementary signals feed the verdict (task 080 mechanism, DO NOT
# duplicate it):
#   1. live claude.exe processes lacking --session-id -- workers always
#      carry it (spawn-agent.ps1 via scripts/lib/spawn-agent-args.ps1), so
#      its absence is "conductor-shaped".
#   2. work/scratch/conductor-session-id -- which session id currently owns
#      the conductor role, and how recently it was re-asserted
#      (config/lib/session-registration.ps1).
#   3. work/messages/conductor/status.json's updatedAt -- stamped on every
#      conductor tool call (config/conductor-status-heartbeat.ps1).
#
# There is no OS-level API that maps a claude.exe pid back to the Claude
# session id it is running (that id never appears on the command line
# unless the process was launched with --resume/--session-id), so this
# logic never CLAIMS to attribute registration to a specific pid unless the
# command line actually contains the registered id -- otherwise it falls
# back to recency (oldest process = likely the stale leftover) and says so.
#
# CIM/file reads stay in the thin script shell (check-conductors.ps1) --
# same split as scripts/lib/agent-proc.ps1 documents for live process code.

function Test-ConductorShapedCommandLine {
    # No --session-id flag => conductor-shaped. A bare/empty command line
    # (nothing captured) is treated as conductor-shaped too -- absence of
    # evidence is not evidence of a worker.
    param([AllowNull()][AllowEmptyString()][string]$CommandLine)
    if ([string]::IsNullOrEmpty($CommandLine)) { return $true }
    return $CommandLine -notmatch '--session-id\b'
}

function Test-HeadlessInvocation {
    # A -p/--print flag means "programmatic one-shot", never an interactive
    # conductor session (2026-07-20 incident: the explorer harness's judge
    # call, `claude.exe -p "..."`, carries no --session-id either and was
    # misclassified as conductor-shaped). claude's only documented way to
    # feed a prompt non-interactively IS -p/--print, so this alone rules out
    # essentially every scripted/harness invocation.
    param([AllowNull()][AllowEmptyString()][string]$CommandLine)
    if ([string]::IsNullOrEmpty($CommandLine)) { return $false }
    return $CommandLine -match '(^|\s)(-p|--print)(\s|$)'
}

function Test-NonConductorWorkingDirectory {
    # The conductor always runs from the main checkout; every worktree
    # (worker sessions, the explorer harness, any future harness that shells
    # out to claude) is a sibling directory, never the main checkout itself.
    # $null/empty WorkingDirectory means "could not be determined" (best-effort
    # live read, scripts/lib/process-cwd.ps1) -- treated as NOT excluded, same
    # convention as Test-ConductorShapedCommandLine's empty-command-line case:
    # absence of evidence must never wrongly hide a real duplicate.
    param(
        [AllowNull()][AllowEmptyString()][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$MainCheckoutRoot
    )
    if ([string]::IsNullOrEmpty($WorkingDirectory)) { return $false }
    $wd = $WorkingDirectory.TrimEnd('\', '/')
    $root = $MainCheckoutRoot.TrimEnd('\', '/')
    return -not $wd.Equals($root, [StringComparison]::OrdinalIgnoreCase)
}

function Get-ConductorShapedProcesses {
    # Filters an already-normalized process list
    # (Pid/StartTime/CommandLine/WorkingDirectory) down to conductor-shaped
    # candidates. Normalization from raw CIM/native reads happens in the
    # thin script -- this takes plain records so it is callable from Pester
    # without a live process anywhere.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Processes,
        [Parameter(Mandatory)][string]$MainCheckoutRoot
    )
    # Unary comma: without it PowerShell unwraps a 0- or 1-element array
    # result into $null / a bare scalar on return (same bug class as
    # Get-BlockedTaskIds in derived-status.ps1).
    return , @($Processes | Where-Object {
        (Test-ConductorShapedCommandLine -CommandLine $_.CommandLine) -and
        -not (Test-HeadlessInvocation -CommandLine $_.CommandLine) -and
        -not (Test-NonConductorWorkingDirectory -WorkingDirectory $_.WorkingDirectory -MainCheckoutRoot $MainCheckoutRoot)
    })
}

function Test-CommandLineMatchesSession {
    # Best-effort positive signal only: true when the registered session id
    # literally appears on this process's command line (a --resume or
    # --session-id launch). A $false does NOT mean "not the conductor" --
    # most conductor sessions are started as a bare `claude` with no id on
    # the command line at all.
    param(
        [AllowNull()][AllowEmptyString()][string]$CommandLine,
        [AllowNull()][AllowEmptyString()][string]$SessionId
    )
    if ([string]::IsNullOrEmpty($CommandLine) -or [string]::IsNullOrEmpty($SessionId)) { return $false }
    return $CommandLine.Contains($SessionId)
}

function Get-ConductorWatchdogReport {
    # The whole verdict, given already-filtered conductor-shaped candidates
    # plus the two freshness signals. Returns an object the thin script just
    # prints and exits with (.ExitCode): 0 for zero-or-one conductor, 1 for
    # duplicates.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Candidates,
        [AllowNull()][AllowEmptyString()][string]$RegisteredSessionId,
        [AllowNull()][Nullable[DateTime]]$RegistrationLastWriteUtc,
        [AllowNull()][Nullable[DateTime]]$StatusUpdatedAtUtc,
        [Parameter(Mandatory)][DateTime]$NowUtc
    )

    $rows = @($Candidates | Sort-Object StartTime | ForEach-Object {
        [PSCustomObject]@{
            Pid             = $_.Pid
            StartTime       = $_.StartTime
            CommandLine     = $_.CommandLine
            RegisteredMatch = Test-CommandLineMatchesSession -CommandLine $_.CommandLine -SessionId $RegisteredSessionId
        }
    })
    $count = $rows.Count
    $isDuplicate = $count -ge 2

    $registrationAgeSeconds = if ($RegistrationLastWriteUtc) { [Math]::Round(($NowUtc - $RegistrationLastWriteUtc).TotalSeconds, 1) } else { $null }
    $statusAgeSeconds = if ($StatusUpdatedAtUtc) { [Math]::Round(($NowUtc - $StatusUpdatedAtUtc).TotalSeconds, 1) } else { $null }
    $lastActiveSeconds = if ($null -ne $statusAgeSeconds) { $statusAgeSeconds } elseif ($null -ne $registrationAgeSeconds) { $registrationAgeSeconds } else { $null }
    $registeredLabel = if ([string]::IsNullOrEmpty($RegisteredSessionId)) { 'not registered' } else { 'registered' }

    $verdict =
        if ($count -eq 0) {
            'OK: no conductor-shaped session detected right now.'
        }
        elseif ($count -eq 1) {
            $activeText = if ($null -ne $lastActiveSeconds) { "last active $($lastActiveSeconds)s ago" } else { 'last active: unknown' }
            "OK: one conductor (pid $($rows[0].Pid), $registeredLabel, $activeText)."
        }
        else {
            $matched = @($rows | Where-Object RegisteredMatch)
            $lines = @()
            $lines += "DUPLICATE: $count conductor-shaped sessions running at once."
            $lines += "Registration file: $registeredLabel" + $(if ($null -ne $registrationAgeSeconds) { ", last touched $($registrationAgeSeconds)s ago" } else { '' }) + '.'
            $lines += 'status.json: ' + $(if ($null -ne $statusAgeSeconds) { "last updated $($statusAgeSeconds)s ago." } else { 'no updatedAt found.' })
            if ($matched.Count -eq 1) {
                $others = ($rows | Where-Object { $_.Pid -ne $matched[0].Pid } | ForEach-Object { $_.Pid }) -join ', '
                $lines += "pid $($matched[0].Pid)'s command line carries the registered session id -- treat that one as the CONFIRMED active conductor. The other pid(s) ($others) are the stale session(s) -- close those terminals."
            }
            else {
                $oldest = $rows[0]
                $newest = $rows[-1]
                $lines += "No process command line carries the registered session id (normal for a plain `"claude`" launch), so pid identity can't be confirmed directly -- use recency instead: the OLDEST session (pid $($oldest.Pid), started $($oldest.StartTime)) is the more likely leftover; the NEWEST (pid $($newest.Pid), started $($newest.StartTime)) is more likely the one just opened."
            }
            $lines += 'Standing rule: the ACTIVE session wins -- the stale one disarms its inbox monitor and stops writing (AGENTS.md double-conductor protocol). Confirm which one is replying in your chat before closing a terminal.'
            $lines -join "`n"
        }

    [PSCustomObject]@{
        Count                  = $count
        IsDuplicate            = $isDuplicate
        ExitCode               = if ($isDuplicate) { 1 } else { 0 }
        Rows                   = $rows
        RegisteredSessionId    = $RegisteredSessionId
        RegistrationAgeSeconds = $registrationAgeSeconds
        StatusAgeSeconds       = $statusAgeSeconds
        Verdict                = $verdict
    }
}
