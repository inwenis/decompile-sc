<#
.SYNOPSIS
Junction/8.3/device-prefix-proof path canonicalisation, shared by every script that must
tell "is this path at or under that protected root" apart from "is this path *spelled* as
being at or under that protected root" -- the two are not the same question on Windows.

.DESCRIPTION
'\\?\C:\x' and '\\.\C:\x' are both valid Windows paths that Test-Path, Join-Path and
CreateProcess all accept, and a plain string-prefix or [IO.Path]::GetFullPath comparison
does not see through them, an 8.3 short name, or a symlink/junction sitting on the path.
A guard built on any of those can be spelled around. Get-CanonicalPath resolves all of it
-- device prefix, `.`/`..`, 8.3 short names, symlinks and junctions -- via the filesystem's
own APIs, so a guard built on its output tests the real path, not whatever spelling arrived
in an argument.

Originally task008's guard in run-with-plugin.ps1 (never touch C:\sc-install); task018's
deploy.ps1 reuses it verbatim rather than re-deriving a second, driftable copy.

Dot-source this file; it defines Get-CanonicalPath and Test-PathUnder in the caller's scope.
#>

if (-not ('SCPath.Native' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace SCPath {
  public static class Native {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern IntPtr CreateFileW(string p, uint access, uint share, IntPtr sa,
                                             uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern uint GetFinalPathNameByHandleW(IntPtr h, StringBuilder buf, uint n, uint flags);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern uint GetLongPathNameW(string s, StringBuilder buf, uint n);

    // The filesystem's own canonical name for an existing path: resolves 8.3
    // short names, symlinks and junctions. null when the path does not exist.
    public static string FinalPath(string path) {
      IntPtr h = CreateFileW(path, 0, 7, IntPtr.Zero, 3 /*OPEN_EXISTING*/,
                             0x02000000 /*FILE_FLAG_BACKUP_SEMANTICS*/, IntPtr.Zero);
      if (h == new IntPtr(-1)) return null;
      try {
        var sb = new StringBuilder(32768);
        uint n = GetFinalPathNameByHandleW(h, sb, (uint)sb.Capacity, 0);
        if (n == 0 || n >= sb.Capacity) return null;
        return sb.ToString();
      } finally { CloseHandle(h); }
    }

    // Long form of a path that may contain 8.3 components. null on failure.
    public static string LongPath(string path) {
      var sb = new StringBuilder(32768);
      uint n = GetLongPathNameW(path, sb, (uint)sb.Capacity);
      if (n == 0 || n >= sb.Capacity) return null;
      return sb.ToString();
    }
  }
}
"@
}

function Get-CanonicalPath {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)

    $p = $Path.Trim()
    if ($p -eq '') { return '' }
    $p = $p.Replace('/', '\')

    # \\?\C:\x and \\.\C:\x -> C:\x ; \\?\UNC\srv\share -> \\srv\share
    if ($p.Length -ge 4 -and $p.StartsWith('\\') -and ($p[2] -eq '?' -or $p[2] -eq '.') -and $p[3] -eq '\') {
        $p = $p.Substring(4)
        if ($p -match '^UNC\\') { $p = '\\' + $p.Substring(4) }
    }

    try { $p = [IO.Path]::GetFullPath($p) } catch { }   # . , .. , trailing dots/spaces

    $long = [SCPath.Native]::LongPath($p)
    if ($long) { $p = $long }

    $final = [SCPath.Native]::FinalPath($p)
    if ($final) {
        if ($final.StartsWith('\\?\UNC\')) { $final = '\\' + $final.Substring(8) }
        elseif ($final.StartsWith('\\?\')) { $final = $final.Substring(4) }
        $p = $final
    }

    return $p.TrimEnd('\')
}

function Test-PathUnder {
    param([string]$Candidate, [string]$Root)
    if (-not $Candidate -or -not $Root) { return $false }
    $r = $Root.TrimEnd('\')
    if ($Candidate.Equals($r, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $Candidate.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase)
}
