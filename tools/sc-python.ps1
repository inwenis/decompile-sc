<#
.SYNOPSIS
One place that answers "which python runs this repo's tools" -- honestly.

.DESCRIPTION
Resolution order:
  1. the calling checkout's own `.venv`;
  2. the MAIN checkout's `.venv`, via `git rev-parse --git-common-dir` -- worktrees are
     cut without a .venv, and junctioning one in leaves the real .venv one recursive
     delete away from destruction;
  3. `python` on PATH -- CI installs requirements.txt into the runner's system python.
Every rejected candidate lands in .Probed with its reason, so a caller's failure message
can say what was looked at. Dot-source this file; it defines Resolve-ScPython.
#>

function Resolve-ScPython {
    [CmdletBinding()]
    param(
        # The checkout the calling script lives in (repo root or worktree root).
        [Parameter(Mandatory)][string]$RepoRoot,
        # A module the interpreter must be able to import (e.g. 'richchk'). A candidate
        # that cannot import it is rejected WITH that reason: an interpreter missing the
        # module fails far from here, in a message that blames something else. Omit for
        # tools with no deps beyond stdlib.
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
