#Requires -Version 7
<#
Pester coverage for clean.ps1 against a throwaway data root: it deletes what runs and tasks
recreate, keeps what is expensive or user-owned, leaves an empty logs\ behind (the plugin
writes there without creating it), and refuses while a game runs or a launch holds the lock.
Offline; Get-Process is mocked so a real StarCraft on the machine changes nothing.
#>

BeforeAll {
    $script:clean = Join-Path (Split-Path $PSScriptRoot -Parent) 'clean.ps1'

    function New-DataRoot {
        param([string[]]$Files)
        $root = Join-Path ([IO.Path]::GetTempPath()) "clean-test-$([guid]::NewGuid())"
        foreach ($f in $Files) { New-Item -ItemType File -Path (Join-Path $root $f) -Force | Out-Null }
        $root
    }
}

Describe 'clean.ps1' {
    BeforeEach {
        Mock Get-Process { } -ParameterFilter { $Name -eq 'StarCraft' }
    }

    It 'refuses and deletes nothing while a StarCraft runs' {
        Mock Get-Process { [pscustomobject]@{ Id = 1 } } -ParameterFilter { $Name -eq 'StarCraft' }
        $root = New-DataRoot 'sc-work\scratch\x.bin'
        try {
            { & $script:clean -DataRoot $root 6>$null } | Should -Throw '*a StarCraft is running*'
            Join-Path $root 'sc-work\scratch\x.bin' | Should -Exist
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'deletes scratch and logs, keeps the install, toolchain, working copy and deployed game' {
        $kept = 'sc-install\Starcraft\StarCraft.exe', 're-tools\gcc\bin\g++.exe',
            'sc-deploy\starcraft-modded\game\StarCraft.exe', 'sc-work\1161-base\StarCraft.exe',
            'sc-work\cnc-ddraw\v7.1.0.0\ddraw.dll', 'sc-work\decomp\StarCraft.exe\index.tsv',
            'sc-work\ghidra\sc.gpr', 'sc-work\registry\baseline.reg'
        $gone = 'sc-deploy\scratch-task070\game\StarCraft.exe', 'sc-work\scratch\x.bin',
            'sc-work\builds\59aa50b\scplugin.dll', 'sc-work\logs\sc-plugin.log',
            'sc-work\logs\070-frames\f.png', 'sc-work\logs\sc-launch.lock'
        $root = New-DataRoot ($kept + $gone)
        try {
            & $script:clean -DataRoot $root 6>$null
            foreach ($f in $kept) { Join-Path $root $f | Should -Exist }
            foreach ($f in $gone) { Join-Path $root $f | Should -Not -Exist }
            @(Get-ChildItem -LiteralPath (Join-Path $root 'sc-work\logs') -Force).Count | Should -Be 0
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses and deletes nothing while a launch holds sc-launch.lock' {
        $root = New-DataRoot 'sc-work\logs\sc-launch.lock', 'sc-work\scratch\x.bin'
        $held = [IO.File]::Open((Join-Path $root 'sc-work\logs\sc-launch.lock'), 'Open', 'ReadWrite', 'None')
        try {
            { & $script:clean -DataRoot $root 6>$null } | Should -Throw '*a launch holds*'
            Join-Path $root 'sc-work\scratch\x.bin' | Should -Exist
        }
        finally {
            $held.Dispose()
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
