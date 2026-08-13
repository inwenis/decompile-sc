#Requires -Version 7
<#
.SYNOPSIS
Build identity for the plugin: what commit a DLL was built from, and whether the
DLL on disk was built from the source next to it.

.DESCRIPTION
Issue #73 / task 056. Nothing used to map a running scplugin.dll back to a
commit. Two incidents came out of that (2026-08-11 a user-reported regression
chased against a stale DLL; 2026-08-12 twenty minutes of hashing three DLLs and
comparing mtimes against commit timestamps to work out which build the user was
actually running).

Hashing the DLL was never the answer and is not the answer now: a hash names the
BINARY, never the TREE it came from, and you need a lookup table you do not have
to go from one to the other. The DLL carries its own identity instead --
build.ps1 stamps a string into it and this file is what writes, reads and
compares that string.

Two values, and they answer different questions:

  buildId    "<short sha>" or "<short sha>+dirty" -- the same string deploy.ps1
             already prints as version=. Answers "which commit". +dirty is not
             cosmetic: it is the flag that says the sha ALONE is a lie, because
             the tree had uncommitted edits when this was built.

  srcDigest  12 hex chars over the CONTENT of tools/plugin/src/* and build.ps1.
             Answers "which source bytes", which is the question a sha cannot
             answer at all once +dirty is set (every dirty build of a branch
             carries the same sha). This is the value the staleness gate
             compares, because it is the only one that changes when you edit a
             file and do not commit -- which is the exact case that silently
             tested the previous DLL.

build.ps1 is IN the digest deliberately: it owns the compiler and linker flags,
so a build.ps1 edit produces a different binary from identical sources, and a
gate that ignored it would call that DLL current.

.NOTES
Dot-source it:  . (Join-Path $PSScriptRoot 'sc-build-id.ps1')
#>

# Deliberately no Set-StrictMode here: this file is DOT-SOURCED, so a mode set
# here would apply to the whole calling script (build.ps1, run-with-plugin.ps1,
# deploy.ps1), none of which was written under it.

function Get-ScSourceDigest {
    <#
    .SYNOPSIS
    12 hex chars over the plugin's source content, order-independent of the
    filesystem's enumeration order and independent of every file timestamp.

    .DESCRIPTION
    File NAME and file BYTES both go in, so renaming a file changes the digest
    even when the bytes are unchanged. Files are sorted ordinally so two runs on
    the same content always agree.

    Timestamps are deliberately NOT part of it: an mtime-based staleness check
    calls a `git checkout` of the same content stale, and calls an edit-then-save
    that restored the original bytes stale too. Content is the thing the compiler
    actually reads.
    #>
    param(
        [Parameter(Mandatory)][string]$SrcDir,
        # build.ps1 -- the flags are part of what the binary IS. Optional only so
        # a caller can digest a bare source tree in a test.
        [string]$BuildScript
    )
    if (-not (Test-Path -LiteralPath $SrcDir)) { throw "Get-ScSourceDigest: no such source dir: $SrcDir" }

    $files = @(Get-ChildItem -LiteralPath $SrcDir -File | Sort-Object -Property Name -CaseSensitive)
    if ($files.Count -eq 0) { throw "Get-ScSourceDigest: $SrcDir holds no files -- refusing to digest an empty tree." }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $parts = [System.Collections.Generic.List[byte[]]]::new()
        foreach ($f in $files) {
            $parts.Add([Text.Encoding]::UTF8.GetBytes("src/$($f.Name)`n"))
            $parts.Add([IO.File]::ReadAllBytes($f.FullName))
        }
        if ($BuildScript) {
            if (-not (Test-Path -LiteralPath $BuildScript)) { throw "Get-ScSourceDigest: no such build script: $BuildScript" }
            $parts.Add([Text.Encoding]::UTF8.GetBytes("build/$(Split-Path $BuildScript -Leaf)`n"))
            $parts.Add([IO.File]::ReadAllBytes($BuildScript))
        }
        $total = 0
        foreach ($p in $parts) { $total += $p.Length }
        $buf = [byte[]]::new($total)
        $at = 0
        foreach ($p in $parts) { [Array]::Copy($p, 0, $buf, $at, $p.Length); $at += $p.Length }
        $hash = $sha.ComputeHash($buf)
    }
    finally { $sha.Dispose() }

    -join ($hash[0..5] | ForEach-Object { $_.ToString('x2') })
}

function Get-ScBuildIdentity {
    <#
    .SYNOPSIS
    The git half: short sha, dirty flag, and the "<sha>+dirty" string.

    .DESCRIPTION
    Same shape and the same +dirty suffix deploy.ps1 already prints, on purpose:
    two mechanisms printing two different version strings for one build is how
    you get a second incident of the first one's class.

    A tree with no git at all is not an error here -- it is what the DEPLOYED
    copy looks like -- but it must never come out looking like a clean build, so
    it reports the sha 'nogit' rather than an empty string.
    #>
    param([Parameter(Mandatory)][string]$RepoRoot)

    # try/catch as well as the exit-code check: with the caller's
    # $ErrorActionPreference = 'Stop' (build.ps1's, and every other script here), a
    # machine with no git at all throws CommandNotFoundException before the exit
    # code is ever looked at. "No git" must degrade to an honest 'nogit+dirty',
    # not kill the build with an unrelated-looking error.
    $sha = $null
    try { $sha = (& git -C $RepoRoot rev-parse --short HEAD 2>$null) } catch { $sha = $null }
    if ($LASTEXITCODE -ne 0 -or -not $sha) {
        return [pscustomobject]@{ Sha = 'nogit'; Dirty = $true; BuildId = 'nogit+dirty' }
    }
    $sha = "$sha".Trim()
    # Tracked AND untracked (--porcelain reports both). An untracked .cpp in src/
    # is compiled by build.ps1's wildcard-free file list only if it is named
    # there, but an untracked HEADER is included by whatever includes it, so
    # "untracked does not count" would be wrong.
    $porcelain = @(& git -C $RepoRoot status --porcelain | Where-Object { $_ })
    $dirty = $porcelain.Count -gt 0
    [pscustomobject]@{
        Sha     = $sha
        Dirty   = $dirty
        BuildId = "$sha$(if ($dirty) { '+dirty' })"
    }
}

function Get-ScDllBuildStamp {
    <#
    .SYNOPSIS
    Read the identity OUT of a built DLL/EXE -- no git, no source, no rebuild.

    .DESCRIPTION
    This is what makes acceptance criterion 4 true: the deployed binary answers
    "what am I" by itself. The stamp is an ordinary NUL-terminated string literal
    in .rdata, so it survives -s (strip removes the symbol table, not the string
    data) and it is readable from a file nobody is running.

    Returns $null when the file carries no stamp at all (a hand-built DLL, or one
    from before task 056) -- callers must treat that as UNKNOWN, never as OK.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { throw "Get-ScDllBuildStamp: no such file: $Path" }
    $bytes = [IO.File]::ReadAllBytes($Path)
    # Latin1 maps every byte 1:1 to a char, so no byte can be lost or folded on
    # the way into the string the regex runs over (UTF8 decoding would mangle
    # >0x7F bytes and could destroy a match that straddled one).
    $text = [Text.Encoding]::Latin1.GetString($bytes)
    # The two literals below are the SAME two src/sc_buildid.cpp concatenates into
    # the embedded string. They are spelled out in both places rather than shared,
    # because nothing can share a constant across a PowerShell script and a C
    # translation unit -- build.ps1 closes that by reading the stamp back out of
    # the DLL it just built and failing if it is not the value it asked for.
    $m = [regex]::Match($text, 'SCPLUGIN_BUILD_ID=([\x21-\x7E]{1,64}) SRC=([0-9a-f]{6,64})')
    if (-not $m.Success) { return $null }
    [pscustomobject]@{
        BuildId   = $m.Groups[1].Value
        SrcDigest = $m.Groups[2].Value
        Stamp     = $m.Value
    }
}

function Test-ScPluginCurrent {
    <#
    .SYNOPSIS
    Is this DLL built from this source tree? Returns a verdict object; throws
    nothing, decides nothing -- the caller decides whether to rebuild or refuse.

    .DESCRIPTION
    The three states are deliberately three, not two:
      current = $true                  the DLL's stamp matches this tree
      current = $false, Stamp = $null  the DLL carries NO stamp -- unknown, and
                                       unknown is not current
      current = $false, Stamp set      it is stamped, from other source bytes
    #>
    param(
        [Parameter(Mandatory)][string]$DllPath,
        [Parameter(Mandatory)][string]$SrcDir,
        [string]$BuildScript
    )
    $expected = Get-ScSourceDigest -SrcDir $SrcDir -BuildScript $BuildScript
    $stamp = Get-ScDllBuildStamp -Path $DllPath
    if (-not $stamp) {
        return [pscustomobject]@{
            Current = $false; Expected = $expected; Stamp = $null
            Reason = "$(Split-Path $DllPath -Leaf) carries NO build stamp (built before task 056, or built by hand rather than by build.ps1). What source it came from cannot be established from the file."
        }
    }
    if ($stamp.SrcDigest -ne $expected) {
        return [pscustomobject]@{
            Current = $false; Expected = $expected; Stamp = $stamp
            Reason = "$(Split-Path $DllPath -Leaf) was built from source $($stamp.SrcDigest) (build $($stamp.BuildId)); this worktree's source is $expected."
        }
    }
    [pscustomobject]@{
        Current = $true; Expected = $expected; Stamp = $stamp
        Reason = "$(Split-Path $DllPath -Leaf) is build $($stamp.BuildId), source $($stamp.SrcDigest) -- matches this worktree."
    }
}
