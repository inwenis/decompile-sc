# Pure(ish) logic for read-message.ps1 (task 130): the atomic move-then-print
# core, collision-safe filing, and unread-message discovery. Split out of the
# CLI wrapper so the race/collision branches are unit-testable without real
# concurrency -- same split the rest of scripts/lib/ uses (pure logic in
# lib/ + tests, live process/CLI glue stays in the untested wrapper script).

function Move-MessageToRead {
    <#
    Moves $SourcePath into $ReadDir, creating $ReadDir if needed and never
    overwriting an existing file there -- suffixes -2, -3, ... instead (the
    2026-07-17 data-loss rule: never overwrite under work/messages/).

    Move-first ordering: this runs BEFORE the caller reads/prints content, so
    a caller that dies mid-invocation either (a) has moved-and-owns the
    message -- safe, the content sits intact in read/, just unprinted, and
    can be re-cat'd from there -- or (b) never touched it -- safe, the
    message is untouched in inbox/. It can never end up shown-as-acted-on
    while still stuck, unfiled, in the inbox: that gray-tick state is exactly
    the bug this script exists to remove.

    Returns the destination path, or $null if another reader already won the
    race and moved $SourcePath out from under us (detected as Move-Item
    failing because the source is gone -- not an error, just "someone else
    already has it").
    #>
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$ReadDir
    )

    if (-not (Test-Path -LiteralPath $ReadDir)) {
        New-Item -ItemType Directory -Path $ReadDir -Force | Out-Null
    }

    $leaf = Split-Path -Path $SourcePath -Leaf
    $stem = [IO.Path]::GetFileNameWithoutExtension($leaf)
    $ext = [IO.Path]::GetExtension($leaf)
    $n = 2
    $dest = Join-Path $ReadDir $leaf

    while ($true) {
        if (Test-Path -LiteralPath $dest) {
            $dest = Join-Path $ReadDir "$stem-$n$ext"
            $n++
            continue
        }
        try {
            Move-Item -LiteralPath $SourcePath -Destination $dest -ErrorAction Stop
            return $dest
        }
        catch {
            if (-not (Test-Path -LiteralPath $SourcePath)) {
                # source vanished between our check and our move -- another
                # reader already claimed this message.
                return $null
            }
            if (Test-Path -LiteralPath $dest) {
                # destination collision race (another reader's move landed
                # between our Test-Path check and our Move-Item) -- retry
                # with the next suffix instead of surfacing the error.
                continue
            }
            throw
        }
    }
}

function Get-UnreadMessages {
    <#
    Files in $InboxDir, oldest first -- the filename's UTC timestamp prefix
    sorts chronologically. Empty array when the inbox is missing or empty:
    that is a normal poll result, not an error.
    #>
    param([Parameter(Mandatory)][string]$InboxDir)

    if (-not (Test-Path -LiteralPath $InboxDir)) { return @() }
    @(Get-ChildItem -LiteralPath $InboxDir -File | Sort-Object Name)
}

function Get-MessageDisplay {
    <#
    Formats a filed message for printing: a path header (repo-relative when
    $FiledPath sits under $Repo, else the raw path) followed by its content.
    #>
    param(
        [Parameter(Mandatory)][string]$FiledPath,
        [Parameter(Mandatory)][string]$Repo
    )

    $content = Get-Content -LiteralPath $FiledPath -Raw
    $rel = if ($FiledPath.StartsWith($Repo, [StringComparison]::OrdinalIgnoreCase)) {
        $FiledPath.Substring($Repo.Length).TrimStart('\', '/') -replace '\\', '/'
    }
    else {
        $FiledPath -replace '\\', '/'
    }
    "=== $rel ===`n$($content.TrimEnd())`n"
}
