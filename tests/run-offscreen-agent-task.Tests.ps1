#Requires -Version 7
<#
run-offscreen.ps1 refuses to start without a numeric $env:AGENT_TASK: left empty, the launch
lock, the foreground hand-back and the per-run fixture folder all switch off without a word.
#>

Describe 'run-offscreen.ps1 without $env:AGENT_TASK' {
    BeforeAll {
        $script:tool = Join-Path $PSScriptRoot '..' 'tools' 'plugin' 'run-offscreen.ps1'
        $script:saved = $env:AGENT_TASK
    }
    AfterAll { $env:AGENT_TASK = $script:saved }

    It 'refuses before it runs anything when AGENT_TASK is <Label>' -TestCases @(
        @{ Label = 'unset'; Value = $null }
        @{ Label = 'not a number'; Value = 'abc' }
    ) {
        $env:AGENT_TASK = $Value
        { & $tool -Command 'exit 0' } | Should -Throw -ExpectedMessage '*set $env:AGENT_TASK*'
    }
}
