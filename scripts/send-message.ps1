#Requires -Version 7
<#
.SYNOPSIS
Send a message to another agent's inbox (file-based agent messaging).

.DESCRIPTION
Writes one markdown file into work/messages/<To>/inbox/. The recipient's inbox
and read/ directories are created on demand. Prints the path of the created file.

Message file name: <UTC yyyyMMdd-HHmmss>-from-<From>[-<slug>].md
Slug defaults to a kebab-case form of -Subject; override with -Slug ''.

Asking the human a question (task 012): -Type question + -Options 'a; b; c'
adds `type:`/`options:` front matter — the console renders one button per
option and writes the answer back as a normal message carrying `re: <id>`.

.EXAMPLE
./scripts/send-message.ps1 -To conductor -From 003 -Subject READY -Body 'watching work/messages/003/inbox/'

.EXAMPLE
./scripts/send-message.ps1 -To 003 -From conductor -Subject 'Scope change' -BodyFile notes.md

.EXAMPLE
./scripts/send-message.ps1 -To user -From 012 -Subject 'Which database for the cache layer?' -Body 'Both work; postgres needs a container.' -Type question -Options 'postgres; sqlite; skip for now'

.EXAMPLE
Conductor's in-room reply to the user in workstream 016's own chat (task 066):
./scripts/send-message.ps1 -To 016 -From conductor -Subject 'On it' -Body 'Looking now.' -Channel user
#>
param(
    [Parameter(Mandatory)][string]$To,
    [Parameter(Mandatory)][string]$From,
    [Parameter(Mandatory)][string]$Subject,
    [string]$Body,
    [string]$BodyFile,
    [string]$Slug,
    [ValidateSet('question')][string]$Type,
    [string]$Options,
    [string]$Re,
    # Task 066: which physical channel to write into. 'worker' (default) is
    # today's flat work/messages/<To>/inbox behavior, unchanged. 'user' nests
    # an extra "user" segment (work/messages/<To>/user/inbox) -- a
    # workstream's own user<->conductor room; the conductor's in-room replies
    # use this.
    [ValidateSet('user', 'worker')][string]$Channel = 'worker',
    # override for fixture-repo testing (task 074 -- no test may write into
    # the real messages/ dir); defaults to the real repo this script lives in
    [string]$Repo = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'

if (-not $Body -and -not $BodyFile) { throw 'Provide -Body or -BodyFile.' }
if ($Body -and $BodyFile) { throw 'Provide -Body or -BodyFile, not both.' }

# A question the human cannot answer is a bug in the asking agent, not a message.
if ($Options -and -not $Type) { throw 'Provide -Type question with -Options.' }
if ($Type -eq 'question') {
    if (-not $Options) { throw 'A question needs -Options (semicolon-separated).' }
    $optionList = @($Options -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($optionList.Count -lt 2) { throw 'A question needs at least two options.' }
}

if ($BodyFile) {
    if (-not (Test-Path -LiteralPath $BodyFile -PathType Leaf)) { throw "BodyFile not found: $BodyFile" }
    $Body = Get-Content -LiteralPath $BodyFile -Raw
}

function ConvertTo-AgentSlug([string]$text) {
    $s = $text.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $s.Trim('-')
}

# agent ids become directory names -- keep them filesystem-safe
foreach ($id in @($To, $From)) {
    if ($id -notmatch '^[A-Za-z0-9._-]+$') { throw "Invalid agent id: '$id' (allowed: letters, digits, . _ -)" }
}

$repoRoot = $Repo
. (Join-Path $PSScriptRoot 'lib/data-root.ps1')
$dataRoot = Get-DataRoot -RepoRoot $repoRoot

# Sender-side stale-heartbeat warning (report 055 P4 part 2 / issue #33): a
# worker whose heartbeat went dark still has a live registry entry, so a
# message dropped in its inbox could sit unread for hours. Warn the sender AT
# SEND TIME instead of leaving them to find out later. Only worker ids (a bare
# number) have a heartbeat at all -- 'user'/'conductor' are exempt.
if ($To -match '^\d+$') {
    . (Join-Path $PSScriptRoot 'lib/agent-lifecycle.ps1')
    $agentsDir = if ($env:CONDUCTOR_AGENTS_DIR) { $env:CONDUCTOR_AGENTS_DIR } else { Join-Path $dataRoot 'scratch/agents' }
    $targetId = Format-TaskId -Task $To
    $entry = Read-AgentRegistryEntry -Path (Join-Path $agentsDir "$targetId.json")
    if ($entry -and -not $entry.stoppedAt) {
        $staleMinutes = 10
        $hbPath = Join-Path $agentsDir "$targetId.heartbeat"
        $isStale = $true
        if (Test-Path -LiteralPath $hbPath) {
            $age = [DateTime]::UtcNow - (Get-Item -LiteralPath $hbPath).LastWriteTimeUtc
            $isStale = $age.TotalMinutes -gt $staleMinutes
        }
        if ($isStale) {
            Write-Warning "target $targetId looks idle/deaf (heartbeat missing or >$staleMinutes min stale) -- conductor may need to respawn"
        }
    }
}

$channelSeg = if ($Channel -eq 'user') { "$To/user" } else { $To }
$inbox = Join-Path $dataRoot "messages/$channelSeg/inbox"
$read = Join-Path $dataRoot "messages/$channelSeg/read"
foreach ($dir in @($inbox, $read)) {
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

$now = [DateTime]::UtcNow
$stamp = $now.ToString('yyyyMMdd-HHmmss')
$sent = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")

if (-not $PSBoundParameters.ContainsKey('Slug')) { $Slug = ConvertTo-AgentSlug $Subject }
else { $Slug = ConvertTo-AgentSlug $Slug }

$base = "$stamp-from-$From"
if ($Slug) { $base = "$base-$Slug" }

# same second + same slug -> disambiguate instead of overwriting
$path = Join-Path $inbox "$base.md"
$n = 2
while (Test-Path -LiteralPath $path) {
    $path = Join-Path $inbox "$base-$n.md"
    $n++
}

# LF endings, written directly: the console's adapter writes message files the
# same way, so a script-written and a UI-written message are byte-compatible
# regardless of the checkout's line-ending settings.
$lines = @('---', "from: $From", "to: $To", "sent: $sent", "subject: $Subject")
if ($Type) { $lines += "type: $Type" }
if ($Options) { $lines += "options: $Options" }
if ($Re) { $lines += "re: $Re" }
$lines += @('---', '', $Body.TrimEnd(), '')

$content = $lines -join "`n"
[IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($false))

Write-Output ($path -replace '\\', '/')
