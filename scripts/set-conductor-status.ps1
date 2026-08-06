#Requires -Version 7
<#
.SYNOPSIS
Update work/messages/conductor/status.json WITHOUT clobbering fields other writers
maintain (the statusline tee owns contextPct; this script owns state/subject/
model/effort and always refreshes updatedAt).

.EXAMPLE
./scripts/set-conductor-status.ps1 -State processing -Subject 'reviewing PR #26'
#>
param(
    [Parameter(Mandatory)][ValidateSet('idle', 'processing')][string]$State,
    [Parameter(Mandatory)][string]$Subject,
    [string]$Model,
    [string]$Effort
)

$ErrorActionPreference = 'Stop'
$path = Join-Path (Split-Path $PSScriptRoot -Parent) 'work/messages/conductor/status.json'

$cur = @{}
if (Test-Path -LiteralPath $path) {
    try { $cur = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable } catch { $cur = @{} }
}

$cur.state = $State
$cur.subject = $Subject
$cur.updatedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
if ($Model) { $cur.model = $Model }
if ($Effort) { $cur.effort = $Effort }

$json = $cur | ConvertTo-Json -Compress:$false
[IO.File]::WriteAllText($path, $json + "`n", [Text.UTF8Encoding]::new($false))
Write-Output $json
