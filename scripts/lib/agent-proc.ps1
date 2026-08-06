# LIVE process/tab helpers for the agent-lifecycle scripts. These touch
# Win32_Process, Start-Process and taskkill, so they are NOT Pester-tested --
# they are exercised by the task 027 live probe (evidence in the PR). The pure,
# testable logic lives in agent-lifecycle.ps1.

function Start-WtTabResolvePid {
    # Open a Windows Terminal tab running an encoded pwsh command, then resolve
    # the tab's pwsh PID. `wt` detaches -- the tab's pwsh is a child of the
    # already-running WindowsTerminal.exe, not of our Start-Process -- so we
    # cannot read the PID from Start-Process. Instead we match the unique
    # -EncodedCommand string on the process command line (proven in the probe).
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$Encoded,
        [switch]$NewWindow,
        [int]$TimeoutSec = 15
    )
    # No -NoExit (task 129): -NoExit unconditionally blocks a script's own
    # `exit N` from ever terminating the process (proven live -- see the PR),
    # which broke the graceful-close sentinel. The wrapper script itself now
    # owns "stay open after an organic finish" via $host.EnterNestedPrompt().
    $window = $NewWindow ? '-1' : '0'
    $wtArgs = @('-w', $window, 'nt', '--title', $Title, '-d', $WorkDir,
        'pwsh', '-EncodedCommand', $Encoded)
    Start-Process wt -ArgumentList $wtArgs

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSec)
    while ([DateTime]::UtcNow -lt $deadline) {
        $p = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine.Contains($Encoded) } |
            Select-Object -First 1
        if ($p) { return [int]$p.ProcessId }
        Start-Sleep -Milliseconds 300
    }
    return $null
}

function Test-ProcessAlive {
    param([Parameter(Mandatory)][int]$ProcessId)
    return [bool](Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function ConvertFrom-RegistryUtcStamp {
    # ISO stamps written by spawn-agent.ps1 ('yyyy-MM-ddTHH:mm:ssZ' /
    # '...fffZ') -> UTC DateTime, $null when absent/unparsable.
    param([AllowNull()][AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    try {
        return [DateTime]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
    } catch { return $null }
}

function Test-ProcessMatchesRegistryEntry {
    # PID-reuse guard (bootstrap review): registry entries survive crashes and
    # reboots with a stale pwshPid intact, and Windows reuses pids -- so a
    # bare "is SOME process alive at that pid" check can tree-kill an
    # unrelated process (worst case: the live conductor's own session, whose
    # transcript never flushes under taskkill). Refuse to treat the pid as
    # ours unless:
    #   * the process still exists AND its image is pwsh, and
    #   * the registry's spawnedAt does not predate the last OS boot
    #     (pids never survive a reboot), and
    #   * when the entry carries pwshStartTime (recorded at spawn), the live
    #     process's StartTime matches it within 5s; a legacy entry without it
    #     falls back to "process started within 120s of spawnedAt".
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)]$Entry
    )
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    if ($p.ProcessName -ne 'pwsh') { return $false }

    $procStartUtc = $null
    try { $procStartUtc = $p.StartTime.ToUniversalTime() } catch { return $false } # access denied -> refuse to kill

    # anchor = the most recent launch stamp we have (resume rewrites the pid,
    # so resumedAt supersedes the original spawnedAt for staleness checks)
    $spawnedAtUtc = ConvertFrom-RegistryUtcStamp -Value ([string]$Entry.spawnedAt)
    $resumedAtUtc = ConvertFrom-RegistryUtcStamp -Value ([string]$Entry.resumedAt)
    $anchorUtc = if ($resumedAtUtc -and (-not $spawnedAtUtc -or $resumedAtUtc -gt $spawnedAtUtc)) { $resumedAtUtc } else { $spawnedAtUtc }

    try {
        $lastBootUtc = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime()
        if ($anchorUtc -and $anchorUtc -lt $lastBootUtc) { return $false } # entry predates boot -> pid is reused
    } catch {}

    $recordedStartUtc = ConvertFrom-RegistryUtcStamp -Value ([string]$Entry.pwshStartTime)
    if ($recordedStartUtc) {
        return ([Math]::Abs(($procStartUtc - $recordedStartUtc).TotalSeconds) -le 5)
    }
    if ($anchorUtc) {
        return ([Math]::Abs(($procStartUtc - $anchorUtc).TotalSeconds) -le 120)
    }
    return $false
}

function Stop-ProcessTree {
    # Kill the pwsh process TREE: /T takes the children (claude -> node), /F
    # forces. Killing the tab's pwsh makes Windows Terminal close that tab.
    param([Parameter(Mandatory)][int]$ProcessId)
    taskkill /PID $ProcessId /T /F 2>&1
}
