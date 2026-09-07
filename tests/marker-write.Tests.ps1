#Requires -Version 7
<#
Pester coverage for Set-ScMarker (tools/plugin/drive-game.ps1).

Why these tests are DETERMINISTIC and not a timing hammer: `Set-Content` opens the file
with FileShare.NONE, so the write fails whenever ANY reader holds it open -- including
the plugin's observer, which polls the marker about four times a second and opens it as
permissively as Windows allows (GENERIC_READ, FILE_SHARE_READ|WRITE|DELETE;
scplugin.cpp PollMarker). Only the overlap is chancy; given overlap the failure is
certain. So the reader below opens the marker with exactly PollMarker's flags and HOLDS
it: an unshared write fails every time, Set-ScMarker succeeds every time.

The first test is the positive control: if `Set-Content` ever stops failing here, this
file tests nothing and must say so out loud instead of going quietly green
(AGENTS.md § "Oracles: absence and defect-era checks").
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'tools' 'plugin' 'drive-game.ps1')

    if (-not ('ScMarkerTest.Native' -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
namespace ScMarkerTest {
  public static class Native {
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Ansi)]
    private static extern IntPtr CreateFileA(string p, uint acc, uint share, IntPtr sa, uint disp, uint flags, IntPtr t);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
    // Byte for byte the open scplugin.cpp PollMarker performs.
    public static IntPtr OpenLikeObserver(string path) {
      return CreateFileA(path, 0x80000000u, 0x1u | 0x2u | 0x4u, IntPtr.Zero, 3, 0x80, IntPtr.Zero);
    }
  }
}
"@
    }

    function New-MarkerFile {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ("sc-marker-" + [Guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $p = Join-Path $dir 'marker.txt'
        Set-Content -LiteralPath $p -Value 'seed' -NoNewline
        $p
    }
}

Describe 'Set-ScMarker survives the plugin observer holding the marker open' {

    It 'POSITIVE CONTROL: Set-Content -- the old write -- fails while the observer holds it' {
        $p = New-MarkerFile
        $h = [ScMarkerTest.Native]::OpenLikeObserver($p)
        try {
            $h | Should -Not -Be ([IntPtr]-1) -Because 'the test could not open the marker the way the plugin does'
            { Set-Content -LiteralPath $p -Value 'nope' -NoNewline -ErrorAction Stop } |
                Should -Throw -Because 'Set-Content opens FileShare.None; this is issue #37 itself'
        }
        finally { [void][ScMarkerTest.Native]::CloseHandle($h); Remove-Item (Split-Path $p) -Recurse -Force }
    }

    It 'writes the label while the observer holds it open' {
        $p = New-MarkerFile
        $h = [ScMarkerTest.Native]::OpenLikeObserver($p)
        try {
            { Set-ScMarker -MarkerPath $p -Label 'baseline-7' } | Should -Not -Throw
            Get-Content -Raw -LiteralPath $p | Should -Be 'baseline-7'
        }
        finally { [void][ScMarkerTest.Native]::CloseHandle($h); Remove-Item (Split-Path $p) -Recurse -Force }
    }

    It 'writes the label while ANOTHER DRIVER holds the same marker open for writing' {
        # Suites aimed at one log directory share one marker, so a second driver can hold
        # it open for writing. FileShare.Read -- what [IO.File]::WriteAllText would use --
        # is not enough for that case; ReadWrite|Delete is.
        $p = New-MarkerFile
        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $other = [IO.FileStream]::new($p, [IO.FileMode]::Create, [IO.FileAccess]::Write, $share)
        try {
            { Set-ScMarker -MarkerPath $p -Label 'other-driver-9' } | Should -Not -Throw
        }
        finally { $other.Dispose(); Remove-Item (Split-Path $p) -Recurse -Force }
    }

    It 'writes no trailing newline -- PollMarker compares the whole line' {
        $p = New-MarkerFile
        try {
            Set-ScMarker -MarkerPath $p -Label 'card-3'
            [IO.File]::ReadAllBytes($p).Length | Should -Be 6
        }
        finally { Remove-Item (Split-Path $p) -Recurse -Force }
    }

    It 'gives up loudly, naming the marker, when the file cannot be written at all' {
        # A write handle opened with FileShare.None is the one thing the share mode
        # cannot get past -- so the retry has to end in a thrown, readable failure
        # rather than a silent no-op that leaves the suite waiting for a scan.
        $p = New-MarkerFile
        $hog = [IO.FileStream]::new($p, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            { Set-ScMarker -MarkerPath $p -Label 'blocked-1' -Tries 2 -BackoffMs 1 } |
                Should -Throw -ExpectedMessage '*could not write the marker*'
        }
        finally { $hog.Dispose(); Remove-Item (Split-Path $p) -Recurse -Force }
    }
}

Describe 'No caller bypasses Set-ScMarker (issue #71 -- the #37 regression guard)' {
    <#
    Set-ScMarker is the ONE place any marker is written: every other writer in the
    .NET/PowerShell toolbox opens the file with a share mode the plugin's observer
    breaks. A docstring cannot hold that rule -- six call sites broke it independently
    -- so this scans the source instead. AST, not grep: the tokeniser drops comments for
    free, so a comment naming `Set-Content` beside the word marker is not a false hit,
    and a call site cannot hide from the guard by moving the cmdlet name into a string.
    #>

    BeforeAll {
        # Every writer whose share mode is wrong for this file: Set-Content is
        # FileShare.None; WriteAllText/Out-File are FileShare.Read, which tolerates the
        # observer but NOT a second driver holding the same marker open.
        $script:BadWriters = @(
            'Set-Content', 'sc', 'Out-File', 'Add-Content', 'ac',
            'WriteAllText', 'WriteAllBytes', 'WriteAllLines', 'AppendAllText'
        )

        function Find-MarkerBypass {
            param([Parameter(Mandatory)][string]$Root)

            $hits = @()
            foreach ($file in Get-ChildItem -LiteralPath $Root -Filter '*.ps1' -File -Recurse) {
                $tokens = $null; $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                    $file.FullName, [ref]$tokens, [ref]$errors)
                if ($errors.Count) { throw "guard could not parse $($file.Name): $($errors[0].Message)" }

                $cmds = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
                foreach ($c in $cmds) {
                    $name = $c.GetCommandName()
                    if ($null -eq $name -or $script:BadWriters -notcontains $name) { continue }
                    if ($c.Extent.Text -notmatch '(?i)marker') { continue }
                    $hits += [pscustomobject]@{
                        File = $file.Name; Line = $c.Extent.StartLineNumber
                        Text = ($c.Extent.Text -replace '\s+', ' ')
                    }
                }

                $calls = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)
                foreach ($m in $calls) {
                    if ($m.Member.Extent.Text -notin $script:BadWriters) { continue }
                    if ($m.Extent.Text -notmatch '(?i)marker') { continue }
                    $hits += [pscustomobject]@{
                        File = $file.Name; Line = $m.Extent.StartLineNumber
                        Text = ($m.Extent.Text -replace '\s+', ' ')
                    }
                }
            }
            , $hits
        }

        $script:PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' 'tools' 'plugin')).Path
    }

    It 'POSITIVE CONTROL: the scan finds a planted bypass' {
        # Without this, a typo in the writer list or the AST walk would make the guard
        # below pass by finding nothing, forever, over any tree at all.
        $dir = Join-Path ([IO.Path]::GetTempPath()) ("sc-guard-" + [Guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            @'
function Send-Probe {
    param([string]$Tag)
    # a comment mentioning Set-Content and marker must NOT be a hit
    Set-Content -LiteralPath $markerPath -Value $Tag -NoNewline
    Set-ScMarker -MarkerPath $markerPath -Label $Tag
    Set-Content -LiteralPath $someOtherFile -Value $Tag
}
'@ | Set-Content -LiteralPath (Join-Path $dir 'planted.ps1') -NoNewline

            $found = Find-MarkerBypass -Root $dir
            $found.Count | Should -Be 1 -Because 'exactly the raw marker write is a bypass -- not the comment, not Set-ScMarker, not the unrelated file write'
            $found[0].Line | Should -Be 4
        }
        finally { Remove-Item $dir -Recurse -Force }
    }

    It 'tools/plugin writes every marker through Set-ScMarker' {
        $found = Find-MarkerBypass -Root $script:PluginRoot
        $report = ($found | ForEach-Object { "  $($_.File):$($_.Line)  $($_.Text)" }) -join "`n"
        $found.Count | Should -Be 0 -Because @"
these call sites bypass Set-ScMarker and reintroduce issue #37 -- Set-Content opens the
marker FileShare.None, so the write throws WITH CERTAINTY whenever the plugin's observer
has it open. Route them through Set-ScMarker:
$report
"@
    }
}
