#Requires -Version 7
<#
.SYNOPSIS
Run an in-game suite and report WHERE ITS WALL CLOCK WENT, phase by phase.

.DESCRIPTION
Task 031 opened with a question nobody could answer from the logs alone: a suite costs
about four minutes, and nobody knew which four minutes. This wrapper answers it without
editing a single suite.

It works because every suite in this repo already announces its own phases on stdout --
`[3] menus: ...`, `[7] watch it drain: ...` -- and already writes a plugin log whose every
line carries a millisecond timestamp. This script stamps the suite's stdout as it streams
(so a `[N]` header becomes a timestamped phase boundary) and then reports:

  * the WHOLE run, from before the fixture is generated to after the process is gone;
  * every `[N] <step>` the suite printed, with its own duration;
  * the four phases that are NOT the suite's own steps, taken from the plugin log:
    launch+injection, menu walk, map load, and the tips dialog.

Nothing here drives the game, takes the launch lock, or writes to the fixture folder. It
is a stopwatch with a transcript, so running a suite under it is the same run.

WHY THE STDOUT STAMP AND NOT Measure-Command. Measure-Command tells you a suite took 244
seconds, which is the number we already had. The step boundaries are what tell you that
130 of those seconds were nine SCVs being built one after another and 25 were
`Start-Sleep` in the menu walk -- and those only exist on stdout.

.EXAMPLE
./tools/plugin/time-suite.ps1 -Suite ./tools/plugin/test-production-queue.ps1 `
    -SuiteArgs @{ FixtureDir = 'C:\sc-work\1161-base\Maps\BroodWar\00-t031' } `
    -PluginLog C:\sc-work\logs\031\production-queue.log `
    -OutFile C:\sc-work\logs\031\timing-prodqueue-before.txt

.EXAMPLE
# Just re-report from a transcript this script already wrote:
./tools/plugin/time-suite.ps1 -ReportOnly C:\sc-work\logs\031\timing-prodqueue-before.txt
#>
[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [Parameter(ParameterSetName = 'Run', Mandatory)]
    [string]$Suite,
    # Splatted into the suite. A hashtable, so a caller passes -FixtureDir/-LogPath/etc
    # exactly as the suite spells them.
    [Parameter(ParameterSetName = 'Run')]
    [hashtable]$SuiteArgs = @{},
    # The suite's own plugin log. Used for the in-game phases (attach, HUD up, tips gone),
    # which stdout cannot see. Optional: without it the step table still works.
    [Parameter(ParameterSetName = 'Run')]
    [string]$PluginLog,
    [Parameter(ParameterSetName = 'Run')]
    [string]$OutFile,

    [Parameter(ParameterSetName = 'Report', Mandatory)]
    [string]$ReportOnly
)

$ErrorActionPreference = 'Stop'

# A suite's own phase headers look like `[3] menus: ...`. `[0]` and `[final]` are headers
# too, and the suite prints assertion lines indented by two spaces -- which is what keeps
# this from matching `  ok   ...`.
$STEP_RE = '^\[(?<n>\d+|final)\]\s*(?<name>.*)$'
$STAMP_RE = '^(?<ts>\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3})\t(?<line>.*)$'

function Write-Stamped {
    param([string]$Line, [System.IO.StreamWriter]$Writer)
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $Writer.WriteLine("$ts`t$Line")
    $Writer.Flush()
    Write-Host $Line
}

function Get-StepSpans {
    param([string[]]$TranscriptLines)
    $steps = @()
    foreach ($l in $TranscriptLines) {
        $m = [regex]::Match($l, $STAMP_RE)
        if (-not $m.Success) { continue }
        $t = [datetime]::ParseExact($m.Groups['ts'].Value, 'yyyy-MM-dd HH:mm:ss.fff', $null)
        $s = [regex]::Match($m.Groups['line'].Value, $STEP_RE)
        if ($s.Success) {
            $steps += [pscustomobject]@{
                N = $s.Groups['n'].Value
                Name = $s.Groups['name'].Value.Trim()
                Start = $t
                End = $t
            }
        }
        elseif ($steps.Count -gt 0) { $steps[-1].End = $t }
    }
    # A step ends where the next one starts, so the gap between them (the suite's own
    # untagged work -- the launch, mostly) is not silently charged to nobody.
    for ($i = 0; $i -lt $steps.Count - 1; $i++) { $steps[$i].End = $steps[$i + 1].Start }
    return $steps
}

function Get-PluginPhases {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $attach = $null; $ingame = $null; $ready = $null; $detach = $null; $last = $null
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $m = [regex]::Match($line, '^\[(?<ts>\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3})\]\s(?<body>.*)$')
        if (-not $m.Success) { continue }
        $t = [datetime]::ParseExact($m.Groups['ts'].Value, 'yyyy-MM-dd HH:mm:ss.fff', $null)
        $last = $t
        $body = $m.Groups['body'].Value
        if ($null -eq $attach -and $body.StartsWith('ATTACH')) { $attach = $t }
        if ($body.StartsWith('DIALOGS')) {
            # The HUD dialogs (Minimap, StatBtn, ...) exist only once the map is LOADED, so
            # the first DIALOGS line naming Minimap is map-load-complete -- read out of the
            # engine's own dialog list rather than off a frame (AGENTS.md, task 026).
            $names = [regex]::Matches($body, "dlg='([^']+)'") | ForEach-Object { $_.Groups[1].Value }
            if ($names -contains 'Minimap') {
                if ($null -eq $ingame) { $ingame = $t }
                if ($null -eq $ready -and $names -notcontains 'Tips_Dlg') { $ready = $t }
            }
        }
        if ($null -eq $detach -and $body.StartsWith('DETACH')) { $detach = $t }
    }
    return [pscustomobject]@{
        Attach = $attach; InGame = $ingame; Ready = $ready
        Detach = $detach; Last = $last
    }
}

function Format-Span { param($A, $B)
    if ($null -eq $A -or $null -eq $B) { return '     -' }
    '{0,6:n1}' -f ($B - $A).TotalSeconds
}

function Write-Report {
    param([string[]]$TranscriptLines, [string]$PluginLogPath)
    $steps = Get-StepSpans -TranscriptLines $TranscriptLines
    if ($steps.Count -eq 0) { Write-Host 'time-suite: no [N] step headers in the transcript.'; return }

    $stamped = @($TranscriptLines | Where-Object { $_ -match $STAMP_RE })
    $t0 = [datetime]::ParseExact([regex]::Match($stamped[0], $STAMP_RE).Groups['ts'].Value, 'yyyy-MM-dd HH:mm:ss.fff', $null)
    $t1 = [datetime]::ParseExact([regex]::Match($stamped[-1], $STAMP_RE).Groups['ts'].Value, 'yyyy-MM-dd HH:mm:ss.fff', $null)
    $total = ($t1 - $t0).TotalSeconds

    Write-Host ''
    Write-Host ('time-suite: {0,6:n1}s wall clock, {1} step(s)' -f $total, $steps.Count)
    Write-Host ''
    Write-Host '  secs    %  step'
    Write-Host '  ----  ---  ----'
    foreach ($s in $steps) {
        $d = ($s.End - $s.Start).TotalSeconds
        Write-Host ('{0,6:n1} {1,4:n0}%  [{2}] {3}' -f $d, (100 * $d / [math]::Max($total, 0.001)), $s.N, $s.Name)
    }

    $p = Get-PluginPhases -Path $PluginLogPath
    if ($p -and $p.Attach) {
        Write-Host ''
        Write-Host '  in-game phases, from the plugin log (these live INSIDE the steps above)'
        Write-Host ('{0}  transcript start -> plugin attached (fixture generation, launch, injection)' -f (Format-Span $t0 $p.Attach))
        Write-Host ('{0}  attached -> the map is loaded (menu walk + map load)' -f (Format-Span $p.Attach $p.InGame))
        Write-Host ('{0}  map loaded -> the tips dialog is gone' -f (Format-Span $p.InGame $p.Ready))
        Write-Host ('{0}  tips gone -> the plugin detached (THE MEASUREMENT)' -f (Format-Span $p.Ready $p.Detach))
        Write-Host ('{0}  detached -> the transcript ends (teardown)' -f (Format-Span $p.Detach $t1))
    }
    elseif ($PluginLogPath) {
        Write-Host ''
        Write-Host "  (no ATTACH line in $PluginLogPath -- in-game phases unavailable)"
    }
}

if ($PSCmdlet.ParameterSetName -eq 'Report') {
    Write-Report -TranscriptLines @(Get-Content -LiteralPath $ReportOnly) -PluginLogPath $PluginLog
    exit 0
}

if (-not (Test-Path -LiteralPath $Suite)) { throw "time-suite: no such suite: $Suite" }
if (-not $OutFile) {
    $OutFile = Join-Path ([System.IO.Path]::GetTempPath()) `
        ("time-suite-{0}.txt" -f [System.IO.Path]::GetFileNameWithoutExtension($Suite))
}
New-Item -ItemType Directory -Path (Split-Path $OutFile -Parent) -Force | Out-Null

Write-Host "time-suite: $Suite -> $OutFile"
$writer = [System.IO.StreamWriter]::new($OutFile, $false)
$suiteExit = 0
try {
    # 6>&1 so the suites' Write-Host lines (which is all of them) come down the pipeline
    # rather than straight to the console, which is what lets them be stamped.
    & $Suite @SuiteArgs 6>&1 2>&1 | ForEach-Object { Write-Stamped -Line "$_" -Writer $writer }
    $suiteExit = $LASTEXITCODE
}
finally {
    $writer.Dispose()
}

Write-Report -TranscriptLines @(Get-Content -LiteralPath $OutFile) -PluginLogPath $PluginLog
Write-Host ''
Write-Host "time-suite: transcript $OutFile (suite exit $suiteExit)"
exit $suiteExit
