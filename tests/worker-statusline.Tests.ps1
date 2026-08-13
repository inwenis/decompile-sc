#Requires -Version 7
<#
Pester case for config/worker-statusline.ps1's cwd release (task 069, issue #96).

WHY THIS EXISTS. The statusline child inherits the worker's cwd, and when its stdin
pipe never closes (a killed tab) it outlives everything, wedged in ReadToEnd -- eleven
such processes were found holding six stranded worktree dirs, one cwd handle each, so
EVERY reaped task stranded its own worktree by construction. The fix moves the Win32
cwd ([Environment]::CurrentDirectory -- Set-Location alone does not release the OS
handle) out of the inherited directory before the blocking read. This case reproduces
the wedge: launch the statusline with its cwd in a temp dir and stdin held open, then
prove the dir is deletable WHILE the process is still alive. Fails against the pre-069
script by construction (the cwd handle blocks Remove-Item).
#>

Describe 'worker-statusline releases its inherited cwd' {

    It 'does not block deletion of its launch directory while wedged on stdin' {
        $root = Join-Path ([IO.Path]::GetTempPath()) "statusline-test-$([guid]::NewGuid().ToString('N'))"
        $launchDir = Join-Path $root 'fake-worktree'
        New-Item -ItemType Directory -Path $launchDir | Out-Null
        $scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '../config/worker-statusline.ps1')).Path

        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = (Get-Command pwsh).Source
        $psi.ArgumentList.Add('-NoProfile'); $psi.ArgumentList.Add('-File'); $psi.ArgumentList.Add($scriptPath)
        $psi.WorkingDirectory = $launchDir
        $psi.RedirectStandardInput = $true   # held OPEN: the wedge every stranded holder was in
        $psi.RedirectStandardOutput = $true
        $psi.UseShellExecute = $false
        $proc = [Diagnostics.Process]::Start($psi)
        try {
            # Give pwsh time to reach the blocking ReadToEnd (past the cwd move).
            # Poll rather than sleep a fixed guess: try the delete until it works
            # or the deadline passes -- pre-fix it NEVER works, post-fix it works
            # as soon as the first lines of the script have run.
            $deadline = [DateTime]::UtcNow.AddSeconds(20)
            $deleted = $false
            while (-not $deleted -and [DateTime]::UtcNow -lt $deadline) {
                $proc.HasExited | Should -BeFalse -Because 'the statusline must still be wedged on stdin while we test the handle'
                try {
                    Remove-Item -LiteralPath $launchDir -Recurse -Force -ErrorAction Stop
                    $deleted = -not (Test-Path -LiteralPath $launchDir)
                }
                catch { Start-Sleep -Milliseconds 250 }
            }
            $deleted | Should -BeTrue -Because 'a wedged statusline process must not hold its launch directory (issue #96: eleven of these stranded six worktrees)'
        }
        finally {
            try { $proc.Kill() } catch { }
            $proc.Dispose()
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
