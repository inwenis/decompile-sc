#Requires -Version 7
<#
Pester coverage for Set-ScMarker (tools/plugin/drive-game.ps1) -- issue #37.

THE BUG THIS PINS. Every marker write was `Set-Content -LiteralPath $MarkerPath`, and a
sweep caught it throwing mid-run:

    FAIL a test step threw: The process cannot access the file
    'C:\sc-work\logs\031\sweep\marker.txt' because it is being used by another process

It was filed as a rare race against the plugin's observer thread, which polls that file
about four times a second. It is neither rare nor a race in the interesting sense:
`Set-Content` opens the file with FileShare.NONE, so the write fails whenever ANY reader
holds it open -- including the plugin's own, which is opened as permissively as Windows
allows (GENERIC_READ, FILE_SHARE_READ|WRITE|DELETE; scplugin.cpp PollMarker). Only the
overlap is chancy; given overlap the failure is certain.

Which is why these tests are DETERMINISTIC rather than a hammer loop: the reader below
opens the marker with exactly PollMarker's flags and HOLDS it, and the old write fails
every time while the new one succeeds every time. A timing probe would only be a slower
way of asking the same question, and a flakier gate.

The positive control is the first test: if `Set-Content` ever stops failing here, this
file is no longer testing anything and should say so out loud instead of going quietly
green (AGENTS.md: an absence assertion is worth nothing until the pattern is shown to
match somewhere it should).
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
        # Task 031's sweep pointed eight suites at one log directory, so they shared one
        # marker. FileShare.Read -- what [IO.File]::WriteAllText would use -- is not
        # enough for that case; ReadWrite|Delete is.
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
