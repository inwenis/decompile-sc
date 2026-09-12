#Requires -Version 7
<#
tools/sc-registry-baseline.ps1 against a throwaway key: a restore must be EXACT (a changed
value back, an added value gone, a deleted subkey back), or "revert to the baseline" leaves
whatever a run added behind.
#>

BeforeAll {
    $script:tool = Join-Path $PSScriptRoot '..' 'tools' 'sc-registry-baseline.ps1'
    $script:key  = "HKCU\SOFTWARE\decompile-sc-pester-$([Guid]::NewGuid().ToString('n'))"
    $script:ps   = "Registry::$($key -replace '^HKCU\\', 'HKEY_CURRENT_USER\')"
    & reg.exe add $key /v A /t REG_DWORD /d 1 /f | Out-Null
    & reg.exe add "$key\Sub" /v C /t REG_SZ /d keep /f | Out-Null
}

AfterAll { & reg.exe delete $key /f 2>&1 | Out-Null }

Describe 'sc-registry-baseline' {
    It 'refuses to restore before a baseline exists, and leaves the key alone' {
        { & $tool -Restore -Key $key -Dir (Join-Path $TestDrive 'none') } | Should -Throw -ExpectedMessage '*-Save goes BEFORE a write*'
        (Get-ItemProperty $ps).A | Should -Be 1
    }

    It 'saves the current state and keeps a timestamped copy' {
        & $tool -Save -Key $key -Dir $TestDrive
        Join-Path $TestDrive 'baseline.reg' | Should -Exist
        @(Get-ChildItem $TestDrive -Filter 'saved-*.reg').Count | Should -Be 1
    }

    It 'restores exactly: changed value back, added value gone, deleted subkey back' {
        & reg.exe add $key /v A /t REG_DWORD /d 9 /f | Out-Null
        & reg.exe add $key /v Added /t REG_SZ /d run /f | Out-Null
        & reg.exe delete "$key\Sub" /f | Out-Null

        & $tool -Restore -Key $key -Dir $TestDrive

        $v = Get-ItemProperty $ps
        $v.A | Should -Be 1
        $v.PSObject.Properties.Name | Should -Not -Contain 'Added'
        (Get-ItemProperty "$ps\Sub").C | Should -Be 'keep'
        @(Get-ChildItem $TestDrive -Filter 'before-restore-*.reg').Count | Should -Be 1
    }
}
