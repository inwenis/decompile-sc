#Requires -Version 7
<#
Pester coverage for the build identity mechanism (issue #73, task 056).

WHAT THIS IS FOR. The mechanism's job is to make two claims falsifiable: "this DLL
came from that source" and "the DLL that ran is the one I vetted". Both rest on
three small functions in tools/plugin/sc-build-id.ps1, and all three fail in the
direction that looks healthy -- a digest that never changes, or a stamp reader
that never matches, both read as "nothing is stale here".

So every assertion below is paired: the thing must MATCH where it should and
CHANGE where it should. A digest test that only checks stability passes for a
function that returns a constant.

Offline: no game, no toolchain, no compiler. The one thing it cannot cover is
whether the -D define survives the real compile -- build.ps1 covers that itself
by reading the stamp back out of the DLL it just built (Assert-BuildStamp), which
is a check that needs the toolchain and therefore lives there, not here.
#>

BeforeAll {
    $script:repoRoot  = Split-Path $PSScriptRoot -Parent
    $script:pluginDir = Join-Path $script:repoRoot 'tools/plugin'
    . (Join-Path $script:pluginDir 'sc-build-id.ps1')

    # A throwaway source tree. Never the real one: these tests mutate files.
    function New-FakeSrc {
        param([hashtable]$Files)
        $dir = Join-Path ([IO.Path]::GetTempPath()) ("scbuildid-" + [Guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        foreach ($name in $Files.Keys) {
            Set-Content -LiteralPath (Join-Path $dir $name) -Value $Files[$name] -NoNewline
        }
        $dir
    }

    # A file whose bytes contain a stamp exactly as the compiler lays one down:
    # the literal, NUL-terminated, surrounded by binary noise.
    function New-FakeDll {
        param([string]$Stamp)
        $path = Join-Path ([IO.Path]::GetTempPath()) ("scbuildid-" + [Guid]::NewGuid().ToString('n') + '.bin')
        $noise = [byte[]]::new(256)
        for ($i = 0; $i -lt $noise.Length; $i++) { $noise[$i] = ($i * 7) % 256 }
        $body = [byte[]]@()
        $body += $noise
        if ($Stamp) { $body += [Text.Encoding]::ASCII.GetBytes($Stamp); $body += [byte]0 }
        $body += $noise
        [IO.File]::WriteAllBytes($path, $body)
        $path
    }
}

Describe 'Get-ScSourceDigest' {

    It 'is stable across calls on unchanged content' {
        $d = New-FakeSrc @{ 'a.cpp' = 'int a;'; 'b.h' = '#define B 1' }
        try { (Get-ScSourceDigest -SrcDir $d) | Should -Be (Get-ScSourceDigest -SrcDir $d) }
        finally { Remove-Item -LiteralPath $d -Recurse -Force }
    }

    It 'CHANGES when one byte of one file changes' {
        # The half that matters. A digest that is merely stable is also achieved by
        # returning a constant, and a constant digest calls every stale DLL current.
        $d = New-FakeSrc @{ 'a.cpp' = 'int a;'; 'b.h' = '#define B 1' }
        try {
            $before = Get-ScSourceDigest -SrcDir $d
            Set-Content -LiteralPath (Join-Path $d 'a.cpp') -Value 'int b;' -NoNewline
            (Get-ScSourceDigest -SrcDir $d) | Should -Not -Be $before
        }
        finally { Remove-Item -LiteralPath $d -Recurse -Force }
    }

    It 'CHANGES when a file is renamed, even though the bytes are identical' {
        $d = New-FakeSrc @{ 'a.cpp' = 'int a;' }
        try {
            $before = Get-ScSourceDigest -SrcDir $d
            Rename-Item -LiteralPath (Join-Path $d 'a.cpp') -NewName 'z.cpp'
            (Get-ScSourceDigest -SrcDir $d) | Should -Not -Be $before
        }
        finally { Remove-Item -LiteralPath $d -Recurse -Force }
    }

    It 'CHANGES when a new file appears' {
        $d = New-FakeSrc @{ 'a.cpp' = 'int a;' }
        try {
            $before = Get-ScSourceDigest -SrcDir $d
            Set-Content -LiteralPath (Join-Path $d 'new.h') -Value 'x' -NoNewline
            (Get-ScSourceDigest -SrcDir $d) | Should -Not -Be $before
        }
        finally { Remove-Item -LiteralPath $d -Recurse -Force }
    }

    It 'ignores mtime -- touching a file without changing it is not a change' {
        # An mtime-based gate would call a fresh `git checkout` of identical source
        # stale and rebuild on every branch switch, which is how a gate gets turned off.
        $d = New-FakeSrc @{ 'a.cpp' = 'int a;' }
        try {
            $before = Get-ScSourceDigest -SrcDir $d
            (Get-Item -LiteralPath (Join-Path $d 'a.cpp')).LastWriteTime = (Get-Date).AddHours(1)
            (Get-ScSourceDigest -SrcDir $d) | Should -Be $before
        }
        finally { Remove-Item -LiteralPath $d -Recurse -Force }
    }

    It 'CHANGES when the build script changes, with the sources untouched' {
        # build.ps1 owns the compile/link flags, so identical sources under different
        # flags are a different binary. A gate blind to that calls it current.
        $d = New-FakeSrc @{ 'a.cpp' = 'int a;' }
        $b1 = Join-Path $d '..\scbuildid-build1.ps1'
        $b2 = Join-Path $d '..\scbuildid-build2.ps1'
        Set-Content -LiteralPath $b1 -Value '-O2' -NoNewline
        Set-Content -LiteralPath $b2 -Value '-O0' -NoNewline
        try {
            (Get-ScSourceDigest -SrcDir $d -BuildScript $b1) |
                Should -Not -Be (Get-ScSourceDigest -SrcDir $d -BuildScript $b2)
        }
        finally { Remove-Item -LiteralPath $d -Recurse -Force; Remove-Item -LiteralPath $b1, $b2 -Force }
    }

    It 'refuses an empty source directory rather than digesting nothing' {
        $d = New-FakeSrc @{}
        try { { Get-ScSourceDigest -SrcDir $d } | Should -Throw '*refusing to digest an empty tree*' }
        finally { Remove-Item -LiteralPath $d -Recurse -Force }
    }
}

Describe 'Get-ScDllBuildStamp' {

    It 'finds a stamp in a binary that has one (the reader is proved positive)' {
        # Without this, every "no stamp" result below is indistinguishable from a
        # reader that never matches anything -- AGENTS.md's absence rule.
        $f = New-FakeDll 'SCPLUGIN_BUILD_ID=abc1234 SRC=0123456789ab'
        try {
            $s = Get-ScDllBuildStamp -Path $f
            $s | Should -Not -BeNullOrEmpty
            $s.BuildId   | Should -Be 'abc1234'
            $s.SrcDigest | Should -Be '0123456789ab'
        }
        finally { Remove-Item -LiteralPath $f -Force }
    }

    It 'keeps the +dirty suffix, which is the part that says the sha alone is a lie' {
        $f = New-FakeDll 'SCPLUGIN_BUILD_ID=abc1234+dirty SRC=0123456789ab'
        try { (Get-ScDllBuildStamp -Path $f).BuildId | Should -Be 'abc1234+dirty' }
        finally { Remove-Item -LiteralPath $f -Force }
    }

    It 'returns $null for a binary with no stamp' {
        $f = New-FakeDll $null
        try { Get-ScDllBuildStamp -Path $f | Should -BeNullOrEmpty }
        finally { Remove-Item -LiteralPath $f -Force }
    }

    It 'reads an UNSTAMPED build as its literal value, never as a match' {
        # sc_buildid.cpp's fallback for a hand-compiled DLL. It must be visible and it
        # must never be mistaken for a source digest.
        $f = New-FakeDll 'SCPLUGIN_BUILD_ID=UNSTAMPED SRC=UNSTAMPED'
        try {
            # SRC=UNSTAMPED is not hex, so the pattern does not match it at all --
            # an unstamped DLL cannot present a src digest of any kind.
            Get-ScDllBuildStamp -Path $f | Should -BeNullOrEmpty
        }
        finally { Remove-Item -LiteralPath $f -Force }
    }
}

Describe 'Test-ScPluginCurrent' {

    It 'says CURRENT when the stamp matches the source' {
        $d = New-FakeSrc @{ 'a.cpp' = 'int a;' }
        $digest = Get-ScSourceDigest -SrcDir $d
        $f = New-FakeDll "SCPLUGIN_BUILD_ID=abc1234 SRC=$digest"
        try {
            $v = Test-ScPluginCurrent -DllPath $f -SrcDir $d
            $v.Current | Should -BeTrue
        }
        finally { Remove-Item -LiteralPath $d -Recurse -Force; Remove-Item -LiteralPath $f -Force }
    }

    It 'says STALE when the source changed under a stamped DLL' {
        $d = New-FakeSrc @{ 'a.cpp' = 'int a;' }
        $f = New-FakeDll "SCPLUGIN_BUILD_ID=abc1234 SRC=$(Get-ScSourceDigest -SrcDir $d)"
        try {
            Set-Content -LiteralPath (Join-Path $d 'a.cpp') -Value 'int changed;' -NoNewline
            $v = Test-ScPluginCurrent -DllPath $f -SrcDir $d
            $v.Current | Should -BeFalse
            $v.Reason  | Should -BeLike '*was built from source*'
        }
        finally { Remove-Item -LiteralPath $d -Recurse -Force; Remove-Item -LiteralPath $f -Force }
    }

    It 'treats an UNSTAMPED DLL as not current -- unknown is never current' {
        $d = New-FakeSrc @{ 'a.cpp' = 'int a;' }
        $f = New-FakeDll $null
        try {
            $v = Test-ScPluginCurrent -DllPath $f -SrcDir $d
            $v.Current | Should -BeFalse
            $v.Stamp   | Should -BeNullOrEmpty
            $v.Reason  | Should -BeLike '*carries NO build stamp*'
        }
        finally { Remove-Item -LiteralPath $d -Recurse -Force; Remove-Item -LiteralPath $f -Force }
    }
}

Describe 'run-with-plugin.ps1 -BuildDir is honoured, not "helpfully" rebuilt' {
    # A NAMED build dir is a deliberate choice: test-random-conformance.ps1 points at
    # C:\sc-work\builds\<sha> to reproduce a bug against the commit before its fix, and
    # README-deploy.md points this script at the user's DEPLOYED plugin dir. A gate that
    # rebuilt into either would destroy the build the caller asked for -- and in the
    # deploy case would overwrite the user's installed binary from a test run.
    #
    # Driven for real, not grepped: -NoLaunch returns after the DLL is resolved, which is
    # where the gate lives, so this exercises the actual code path with no game and no
    # compiler. The DLL is a fake carrying a stamp that does NOT match this worktree,
    # which is exactly the state that triggers a rebuild in the default dir.

    BeforeAll {
        $script:runner  = Join-Path $script:pluginDir 'run-with-plugin.ps1'
        $script:gameDir = 'C:\sc-work\1161-base'
    }

    It 'leaves a stale DLL in a named -BuildDir untouched, and says so' -Skip:(-not (Test-Path 'C:\sc-work\1161-base')) {
        $bd = Join-Path ([IO.Path]::GetTempPath()) ("scbuilddir-" + [Guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $bd -Force | Out-Null
        try {
            $fake = New-FakeDll 'SCPLUGIN_BUILD_ID=0000000 SRC=000000000000'
            Copy-Item -LiteralPath $fake -Destination (Join-Path $bd 'scplugin.dll')
            Copy-Item -LiteralPath $fake -Destination (Join-Path $bd 'scinject.exe')
            Remove-Item -LiteralPath $fake -Force
            $beforeHash = (Get-FileHash -LiteralPath (Join-Path $bd 'scplugin.dll') -Algorithm SHA256).Hash

            $out = & $script:runner -NoLaunch -NoLaunchLock -BuildDir $bd -GameDir $script:gameDir 3>&1 2>&1 | Out-String

            # The bytes are the assertion. A rebuild would replace them with a real DLL.
            (Get-FileHash -LiteralPath (Join-Path $bd 'scplugin.dll') -Algorithm SHA256).Hash |
                Should -Be $beforeHash -Because 'a named -BuildDir must never be rebuilt into'
            # And it must not go quietly: silence here is the defect this whole task is about.
            $out | Should -BeLike '*NOT this worktree*'
            $out | Should -BeLike '*Nothing was rebuilt*'
        }
        finally { Remove-Item -LiteralPath $bd -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'the pieces are actually wired together' {

    It 'build.ps1 passes both defines and verifies the stamp it got back' {
        $t = Get-Content -Raw -LiteralPath (Join-Path $script:pluginDir 'build.ps1')
        $t | Should -BeLike '*-DSC_BUILD_ID=*'
        $t | Should -BeLike '*-DSC_BUILD_SRC=*'
        $t | Should -BeLike '*Assert-BuildStamp*'
    }

    It 'build.ps1 pins the two things that made the build non-reproducible' {
        $t = Get-Content -Raw -LiteralPath (Join-Path $script:pluginDir 'build.ps1')
        $t | Should -BeLike '*--no-insert-timestamp*'
        $t | Should -BeLike '*--image-base=*'
    }

    It 'sc_buildid.cpp is in the plugin source list' {
        # Compiles clean if it is missing -- nothing else references it -- and the DLL
        # would simply carry no stamp. build.ps1 would then fail at Assert-BuildStamp,
        # but only on a machine with the toolchain; this catches it everywhere.
        $t = Get-Content -Raw -LiteralPath (Join-Path $script:pluginDir 'build.ps1')
        $t | Should -BeLike "*'sc_buildid.cpp'*"
    }

    It 'the ATTACH banner logs the stamp' {
        $t = Get-Content -Raw -LiteralPath (Join-Path $script:pluginDir 'src/scplugin.cpp')
        $t | Should -BeLike '*ScBuildStampShort()*'
    }

    It 'run-with-plugin.ps1 gates the launch on it' {
        $t = Get-Content -Raw -LiteralPath (Join-Path $script:pluginDir 'run-with-plugin.ps1')
        $t | Should -BeLike '*Test-ScPluginCurrent*'
        $t | Should -BeLike '*STALE PLUGIN*'
    }
}
