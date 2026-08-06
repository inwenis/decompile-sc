# Pure helpers for building the claude command line spawn-agent.ps1 launches.
# No side effects (no Start-Process, no env/registry/filesystem writes) so
# tests can dot-source this file directly and exercise the arg-building
# logic without ever spawning a Windows Terminal tab.

function Build-ClaudeArgs {
    param(
        [string]$Prompt,
        # resume mode: emit `--resume <id>` instead of a bare prompt positional.
        # A resumed worker keeps the SAME settings/permission flags as spawn.
        [string]$ResumeSessionId,
        # spawn mode: pin the new session to a known id (--session-id) so resume
        # is deterministic. Needed because claude canonicalizes a git-worktree
        # cwd to the MAIN repo's ~/.claude/projects dir -- so "newest transcript
        # under the mangled workDir" is unreliable for worktree workers.
        [string]$SessionId,
        [Parameter(Mandatory)][string]$ConductorRepo,
        [ValidateSet('full', 'default', 'acceptEdits', 'plan', 'bypass')]
        [string]$Permissions = 'full',
        [string]$Model,
        [switch]$Chrome
    )

    if (-not $Prompt -and -not $ResumeSessionId) {
        throw 'Build-ClaudeArgs needs -Prompt (spawn) or -ResumeSessionId (resume).'
    }

    $claudeArgs = [System.Collections.Generic.List[string]]::new()
    if ($ResumeSessionId) {
        # --resume + its id first; an optional follow-up prompt goes right
        # after the id (never trailing after a variadic flag like --allowedTools)
        $claudeArgs.AddRange([string[]]@('--resume', $ResumeSessionId))
        if ($Prompt) { $claudeArgs.Add($Prompt) }
    }
    else {
        # prompt FIRST: variadic flags like --allowedTools swallow a trailing
        # positional prompt as their own value (task 010 stillborn lesson)
        $claudeArgs.Add($Prompt)
    }
    $claudeArgs.AddRange([string[]]@('--add-dir', ($ConductorRepo -replace '\\', '/')))
    # full = worker-settings.json (broad allow + ask-list + all guard hooks --
    # a human is expected to answer prompts in that tab). Every other mode =
    # worker-settings-hooks-only.json (deny hooks only, no permissions block):
    # explicit ask rules prompt even under --dangerously-skip-permissions, so
    # loading the ask-list under bypass re-freezes workers nobody is watching
    # (task 013 hole reopened task 001's bug; fixed in task 014).
    $repoSlash = $ConductorRepo -replace '\\', '/'
    $settingsFile = if ($Permissions -eq 'full') { 'worker-settings.json' } else { 'worker-settings-hooks-only.json' }
    $settingsPath = "$repoSlash/config/$settingsFile"
    $claudeArgs.AddRange([string[]]@('--settings', $settingsPath))
    if ($Permissions -eq 'bypass') {
        # skip-permissions flag stays IN ADDITION to --settings: the
        # hooks-only file's deny hooks still fire under bypass (that's the
        # point) -- there is no ask/permissions block left to skip
        $claudeArgs.Add('--dangerously-skip-permissions')
    }
    elseif ($Permissions -ne 'full' -and $Permissions -ne 'default') {
        $claudeArgs.AddRange([string[]]@('--permission-mode', $Permissions))
    }
    if ($SessionId -and -not $ResumeSessionId) { $claudeArgs.AddRange([string[]]@('--session-id', $SessionId)) }
    if ($Model) { $claudeArgs.AddRange([string[]]@('--model', $Model)) }
    if ($Chrome) {
        # enable integration AND pre-approve all claude-in-chrome tools,
        # otherwise every browser call prompts in the tab
        $claudeArgs.Add('--chrome')
        $claudeArgs.AddRange([string[]]@('--allowedTools', 'mcp__claude-in-chrome'))
    }
    return $claudeArgs
}

function Test-NeedsSetup {
    # decision logic only -- no filesystem access here so it's Pester-testable
    # without a real checkout. Caller (spawn-agent.ps1) does the actual
    # Test-Path calls and passes the results in.
    #
    # A worktree missing the setup sentinel (this repo: the .venv python that
    # setup.ps1 creates) needs setup.ps1 run before claude starts (ground
    # rule 6: a worktree is one command from working, not zero-minus-one).
    # The main conductor checkout is excluded: it is set up once by a human,
    # never auto-setup'd on every spawn.
    param(
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$ConductorRepo,
        [Parameter(Mandatory)][bool]$SetupSentinelExists
    )
    $workDirNorm = ($WorkDir -replace '\\', '/').TrimEnd('/')
    $repoNorm = ($ConductorRepo -replace '\\', '/').TrimEnd('/')
    if ($workDirNorm -eq $repoNorm) { return $false }
    return -not $SetupSentinelExists
}

function ConvertTo-PSArrayLiteral {
    # Single-quotes each arg (doubling an embedded quote) and renders a real
    # PowerShell array literal (comma-joined, wrapped in @( )) so the
    # generated wrapper script (task 129) can splat it into
    # ProcessStartInfo.ArgumentList instead of re-parsing a quoted string.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ArgsList
    )
    if ($ArgsList.Count -eq 0) { return '@()' }
    $items = ($ArgsList | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ', '
    return "@($items)"
}

function Build-WorkerWrapperCommand {
    # task 129 -- graceful tab-close. Today's launch is a single blocking
    # `claude <args>` line under `pwsh -NoExit`: killing that pwsh (stop-agent's
    # taskkill /T /F) yanks the whole pane process abruptly, which WT's default
    # closeOnExit=graceful reads as a crash (banner stays, tab does not close --
    # graceful only fires on a self-directed exit code 0).
    #
    # This renders a small wrapper SCRIPT (not a one-liner) that runs claude as
    # a non-blocking child (ProcessStartInfo, console inherited -- fully
    # interactive, same window) so the wrapping pwsh can concurrently poll a
    # sentinel file while claude runs in the foreground:
    #   - sentinel appears (reap-agent.ps1 dropped it) -> kill the claude child
    #     tree, then `exit 0` -- a self-directed graceful exit WT auto-closes.
    #   - claude exits on its own (organic completion/crash, no sentinel) ->
    #     the loop ends and the script calls $host.EnterNestedPrompt() --
    #     tab stays open at an interactive prompt, unchanged UX for a worker
    #     nobody asked to reap.
    #
    # IMPORTANT (proven live, not by inspection): pwsh's own -NoExit flag
    # unconditionally suppresses an explicit `exit N` from the initial
    # -Command/-EncodedCommand script -- `pwsh -NoExit -Command "exit 0"`
    # never terminates the process, it just drops to the prompt. That broke
    # the very first version of this wrapper (the sentinel branch's `exit 0`
    # was silently a no-op under -NoExit) and is WHY the caller must launch
    # this wrapper WITHOUT -NoExit (see Start-WtTabResolvePid) -- this
    # function owns BOTH outcomes itself: a real `exit 0` for the graceful
    # path, EnterNestedPrompt() standing in for what -NoExit used to give for
    # free on the organic path.
    #
    # ClaudePath is the RESOLVED executable path (caller's `(Get-Command
    # claude).Source`), not a bare name -- ProcessStartInfo skips pwsh's own
    # PATH/shim resolution, so passing 'claude' bare would need to re-implement
    # that lookup here.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ClaudeArgs,
        [Parameter(Mandatory)][string]$SentinelPath,
        [Parameter(Mandatory)][string]$ClaudePath,
        [string]$EnvPrefix = '',
        [int]$PollMilliseconds = 500
    )
    $argsLiteral = ConvertTo-PSArrayLiteral -ArgsList $ClaudeArgs
    $claudePathLiteral = "'" + (($ClaudePath -replace '\\', '/') -replace "'", "''") + "'"
    $sentinelLiteral = "'" + (($SentinelPath -replace '\\', '/') -replace "'", "''") + "'"
    return @"
${EnvPrefix}`$claudeArgs = $argsLiteral
`$psi = [Diagnostics.ProcessStartInfo]::new($claudePathLiteral)
foreach (`$a in `$claudeArgs) { `$psi.ArgumentList.Add(`$a) }
`$psi.UseShellExecute = `$false
`$proc = [Diagnostics.Process]::Start(`$psi)
`$sentinel = $sentinelLiteral
while (-not `$proc.HasExited) {
    if (Test-Path -LiteralPath `$sentinel) {
        try { taskkill /PID `$proc.Id /T /F } catch {}
        Remove-Item -LiteralPath `$sentinel -Force -ErrorAction SilentlyContinue
        exit 0
    }
    Start-Sleep -Milliseconds $PollMilliseconds
}
`$host.EnterNestedPrompt()
"@
}

function Format-EnvPrefix {
    param(
        [hashtable]$Env
    )
    if (-not $Env) { return '' }
    return (($Env.GetEnumerator() | ForEach-Object { "`$env:$($_.Key)='$($_.Value)'" }) -join '; ') + '; '
}
