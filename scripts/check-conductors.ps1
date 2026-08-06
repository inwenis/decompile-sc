#Requires -Version 7
<#
.SYNOPSIS
Detect whether more than one conductor-shaped claude.exe session is running
right now, and report which one is likely the real one. Detection + evidence
only -- never kills a process, never writes state. (Task 089, USER REQUEST
2026-07-20: "the double conductor -- when i started the new conductor I'm
pretty sure i killed other terminals, can you write a script that we will
temporarily run that will check if this happens again.")

.DESCRIPTION
Combines three complementary signals that already exist (task 080 -- see
work/scratch/conductor-session-id, config/lib/session-registration.ps1,
config/conductor-status-heartbeat.ps1; DO NOT duplicate that mechanism):
  1. live claude.exe processes lacking --session-id (workers always carry it
     from spawn-agent.ps1) -- "conductor-shaped".
  2. work/scratch/conductor-session-id -- which session id currently owns
     the conductor role, and how recently it was re-asserted.
  3. work/messages/conductor/status.json's updatedAt -- stamped on every
     conductor tool call.

Zero or one conductor-shaped process -> one-line OK. Two or more -> a
numbered table (pid, started, whether the command line carries the
registered session id, command line) plus a plain-language verdict. Exit
code is 0 for zero-or-one, non-zero for duplicates, so this can be wired
into a watcher later.

The verdict logic is pure and Pester-tested (scripts/lib/conductor-watchdog.ps1
/ tests/conductor-watchdog.Tests.ps1); this script only does the live
CIM/file reads, same split scripts/lib/agent-proc.ps1 documents for
live-process code that isn't unit-tested.

.EXAMPLE
./scripts/check-conductors.ps1

.EXAMPLE
./scripts/check-conductors.ps1 -Watch -IntervalSeconds 30
#>
param(
    # override for fixture-repo testing/demos; defaults to the real repo
    # this script lives in
    [string]$Repo = (Split-Path $PSScriptRoot -Parent),
    # loop and print only when the set of conductor-shaped processes changes
    # -- the "temporarily run it" mode the user asked for
    [switch]$Watch,
    [int]$IntervalSeconds = 15
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/conductor-watchdog.ps1')
. (Join-Path $PSScriptRoot 'lib/data-root.ps1')
. (Join-Path $PSScriptRoot 'lib/iso-utc.ps1')
. (Join-Path $PSScriptRoot 'lib/conductor-live-report.ps1')

function Write-ConductorReport {
    param($Report)
    if ($Report.IsDuplicate) {
        Write-Output ('{0,-4} {1,-8} {2,-20} {3,-9} {4}' -f '#', 'PID', 'STARTED (local)', 'REG-ID?', 'COMMAND LINE')
        $i = 0
        foreach ($row in $Report.Rows) {
            $i++
            $started = if ($row.StartTime) { $row.StartTime.ToString('yyyy-MM-dd HH:mm:ss') } else { 'unknown' }
            Write-Output ('{0,-4} {1,-8} {2,-20} {3,-9} {4}' -f $i, $row.Pid, $started, $(if ($row.RegisteredMatch) { 'yes' } else { 'no' }), $row.CommandLine)
        }
        Write-Output ''
    }
    Write-Output $Report.Verdict
}

if (-not $Watch) {
    $report = Get-LiveConductorReport -Repo $Repo
    Write-ConductorReport -Report $report
    exit $report.ExitCode
}

Write-Output "Watching for duplicate conductor sessions every ${IntervalSeconds}s (Ctrl+C to stop)..."
$lastSignature = $null
while ($true) {
    $report = Get-LiveConductorReport -Repo $Repo
    if ($report.Signature -ne $lastSignature) {
        Write-Output "--- $([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ssZ')) ---"
        Write-ConductorReport -Report $report
        $lastSignature = $report.Signature
    }
    Start-Sleep -Seconds $IntervalSeconds
}
