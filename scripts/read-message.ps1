#Requires -Version 7
<#
.SYNOPSIS
Read an inbox message and file it -- one atomic act (task 130).

.DESCRIPTION
Reading a message and marking it read used to be two steps: cat it, act on
it, then (later, separately) Move-Item it to read/. Under load the move
lagged or was forgotten, leaving a message that was already acted on still
showing as unread (gray tick). This script fuses the two into one
invocation: it moves the file into the sibling read/ dir FIRST, then prints
its content from the new location. See scripts/lib/read-message-core.ps1
for why move-first is the order that cannot lose a message.

Pick a message with -Path (an exact file inside an inbox/ dir), or -Agent
(defaults to that agent's newest unread message). -All processes every
unread message in an agent's inbox, oldest first, printing each with a
path header.

.EXAMPLE
./scripts/read-message.ps1 -Agent conductor

.EXAMPLE
./scripts/read-message.ps1 -Path work/messages/130/inbox/20260806-084944-from-130-ready.md

.EXAMPLE
./scripts/read-message.ps1 -Agent conductor -All
#>
param(
    [string]$Path,
    [string]$Agent,
    [switch]$All,
    # override for fixture-repo testing (task 074 -- no test may write into
    # the real messages/ dir); defaults to the real repo this script lives in
    [string]$Repo = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'

if ($Path -and $Agent) { throw 'Provide -Path or -Agent, not both.' }
if (-not $Path -and -not $Agent) { throw 'Provide -Path or -Agent.' }
if ($All -and $Path) { throw '-All requires -Agent, not -Path.' }
if ($Agent -and $Agent -notmatch '^[A-Za-z0-9._-]+$') { throw "Invalid agent id: '$Agent' (allowed: letters, digits, . _ -)" }

. (Join-Path $PSScriptRoot 'lib/data-root.ps1')
. (Join-Path $PSScriptRoot 'lib/read-message-core.ps1')
$dataRoot = Get-DataRoot -RepoRoot $Repo

function Show-FiledMessage {
    param([string]$SourcePath, [string]$ReadDir)
    $dest = Move-MessageToRead -SourcePath $SourcePath -ReadDir $ReadDir
    if (-not $dest) {
        Write-Warning "already filed (raced with another reader): $SourcePath"
        return
    }
    Write-Output (Get-MessageDisplay -FiledPath $dest -Repo $Repo)
}

if ($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Message not found: $Path" }
    $absPath = (Resolve-Path -LiteralPath $Path).Path
    $inboxDir = Split-Path -Path $absPath -Parent
    if ((Split-Path -Path $inboxDir -Leaf) -ne 'inbox') {
        throw "Path must be a message file inside an inbox/ directory: $Path"
    }
    $readDir = Join-Path (Split-Path -Path $inboxDir -Parent) 'read'
    Show-FiledMessage -SourcePath $absPath -ReadDir $readDir
    exit 0
}

$agentDir = Join-Path $dataRoot "messages/$Agent"
$inboxDir = Join-Path $agentDir 'inbox'
$readDir = Join-Path $agentDir 'read'
$files = Get-UnreadMessages -InboxDir $inboxDir

if (-not $files) {
    Write-Output "No unread messages for $Agent."
    exit 0
}

if ($All) {
    foreach ($f in $files) {
        Show-FiledMessage -SourcePath $f.FullName -ReadDir $readDir
    }
    exit 0
}

Show-FiledMessage -SourcePath $files[-1].FullName -ReadDir $readDir
