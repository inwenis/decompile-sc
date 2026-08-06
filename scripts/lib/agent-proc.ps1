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

function Stop-ProcessTree {
    # Kill the pwsh process TREE: /T takes the children (claude -> node), /F
    # forces. Killing the tab's pwsh makes Windows Terminal close that tab.
    param([Parameter(Mandatory)][int]$ProcessId)
    taskkill /PID $ProcessId /T /F 2>&1
}
