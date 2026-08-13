<#
.SYNOPSIS
One place that answers "which python runs this repo's tools" -- honestly.

.DESCRIPTION
Task 069, issue #97. Worktrees are cut without a .venv (only the main checkout has
one), and the old per-script fallback chain ended at whatever `python` sits on PATH.
On this machine that interpreter has no richchk, so map generation failed AFTER the
warning had scrolled by, the map was never written, and the first loud message the
worker saw was drive-game blaming a concurrent worker's cleanup for the missing file.

Resolution order:
  1. the calling checkout's own `.venv` (main checkout, or a worktree someone
     provisioned);
  2. the MAIN checkout's `.venv`, found through `git rev-parse --git-common-dir` --
     this is what closes the worktree gap without junctioning anything into worktrees
     (a junctioned .venv is one recursive delete away from destroying the real one);
  3. `python` on PATH -- kept because CI installs requirements.txt into the runner's
     system python, but ONLY accepted after proving it can `import` the module the
     caller needs. An interpreter that cannot is reported in Probed, never silently
     used.

Every candidate that was tried and rejected lands in .Probed with the reason, so a
caller's failure message can say what was looked at instead of guessing.

Dot-source this file; it defines Resolve-ScPython in the caller's scope.
#>

function Resolve-ScPython {
    [CmdletBinding()]
    param(
        # The checkout the calling script lives in (repo root or worktree root).
        [Parameter(Mandatory)][string]$RepoRoot,
        # A module the interpreter must be able to import (e.g. 'richchk'). A
        # candidate that cannot import it is rejected WITH that reason -- the exact
        # silent failure issue #97 is about. Omit for tools with no deps beyond stdlib.
        [string]$RequireModule
    )

    $probed = [Collections.Generic.List[string]]::new()

    $candidates = [Collections.Generic.List[object]]::new()
    $ownRoot = [IO.Path]::GetFullPath($RepoRoot)
    $candidates.Add(@{ Path = Join-Path $ownRoot '.venv/Scripts/python.exe'; Source = "this checkout's .venv" })

    # A worktree's --git-common-dir is <main checkout>/.git; the main checkout's is
    # its own. Resolve it, and only add the candidate when it is a DIFFERENT root.
    $commonDir = git -C $RepoRoot rev-parse --path-format=absolute --git-common-dir 2>$null
    if ($LASTEXITCODE -eq 0 -and $commonDir) {
        $mainRoot = [IO.Path]::GetFullPath((Split-Path -Parent ("$commonDir".Trim())))
        if ($mainRoot -and $mainRoot -ne $ownRoot) {
            $candidates.Add(@{ Path = Join-Path $mainRoot '.venv/Scripts/python.exe'; Source = "main checkout's .venv ($mainRoot)" })
        }
    }

    $pathPython = (Get-Command python -ErrorAction SilentlyContinue).Source
    if ($pathPython) { $candidates.Add(@{ Path = $pathPython; Source = 'python on PATH' }) }
    else { $probed.Add('python on PATH: not present') }

    foreach ($c in $candidates) {
        if (-not (Test-Path -LiteralPath $c.Path)) {
            $probed.Add("$($c.Source): no interpreter at $($c.Path)")
            continue
        }
        if ($RequireModule) {
            $importOk = $false
            try {
                & $c.Path -c "import $RequireModule" 2>$null | Out-Null
                $importOk = ($LASTEXITCODE -eq 0)
            }
            catch { }
            if (-not $importOk) {
                $probed.Add("$($c.Source) ($($c.Path)): cannot import $RequireModule")
                continue
            }
        }
        return [pscustomobject]@{ Path = $c.Path; Source = $c.Source; Probed = @($probed) }
    }

    return [pscustomobject]@{ Path = $null; Source = $null; Probed = @($probed) }
}
