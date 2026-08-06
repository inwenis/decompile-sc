# Shared conductor session_id registration (task 080 diagnosis b). Two
# writers, one reader:
#   - conductor-sessionstart.ps1 registers at SessionStart (its own guards
#     already ensure only a conductor-shaped session reaches that line).
#   - conductor-status-heartbeat.ps1 (PostToolUse) RE-ASSERTS the same
#     registration on every conductor tool call. A leftover /resume session
#     in the main checkout also fires SessionStart once -- it can win the
#     race and register itself -- but only the ACTIVELY-WORKING conductor
#     keeps firing tool calls, so re-asserting here converges the file to
#     the true conductor within one call.
#   - conductor-statusline.sh reads the file back to decide whether ITS
#     session owns work/messages/conductor/status.json.

function Get-SessionIdFromHookJson {
    param([Parameter(Mandatory)][string]$Raw)
    # Targeted regex scan (worker-id.ps1's pattern), not a full
    # ConvertFrom-Json -- this runs on every tool call and must stay cheap.
    $m = [regex]::Match($Raw, '"session_id"\s*:\s*"((?:[^"\\]|\\.)*)"')
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value
}

function Set-ConductorSessionRegistration {
    param(
        [string]$SessionId,
        [Parameter(Mandatory)][string]$Path
    )
    if (-not $SessionId) { return }
    [IO.Directory]::CreateDirectory((Split-Path $Path -Parent)) | Out-Null
    [IO.File]::WriteAllText($Path, $SessionId, [Text.UTF8Encoding]::new($false))
}
