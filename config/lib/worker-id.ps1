# Shared cwd -> worker-id (NNN) derivation, used by heartbeat.ps1 (PreToolUse
# + PostToolUse) and worker-statusline.ps1 (statusLine). Kept as a targeted
# regex scan, not a full ConvertFrom-Json, so callers stay cheap on every tool
# call / statusline render regardless of payload size (task 032's original
# rationale, now shared by two callers -- task 073).

function Get-CwdFromHookJson {
    param([Parameter(Mandatory)][string]$Raw)
    # JSON escapes backslashes as \\ inside the value, which
    # (?:[^"\\]|\\.)* tolerates.
    $m = [regex]::Match($Raw, '"cwd"\s*:\s*"((?:[^"\\]|\\.)*)"')
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value
}

function Get-WorkerIdFromCwd {
    # A worker's cwd is its worktree C:\git\decompile-sc-taskNNN -> NNN.
    # Main-checkout sessions (plain `decompile-sc`, no -taskNNN suffix) have no
    # worker identity -> $null.
    param([string]$Cwd)
    if (-not $Cwd) { return $null }
    $idm = [regex]::Match($Cwd, 'decompile-sc-task(\d+)')
    if (-not $idm.Success) { return $null }
    return '{0:D3}' -f [int]$idm.Groups[1].Value
}
