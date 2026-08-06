# Pure schtasks argument construction for the weekly mutation-check
# registration (task 110). Same shape as scripts/lib/explorer-schedule.ps1
# (task 109) -- /SC WEEKLY /D instead of /SC DAILY, since the mutation audit
# only needs to re-run when core code actually changes, not every night. No
# Start-Process/schtasks.exe here -- that live glue stays in
# scripts/register-mutation-run.ps1 / scripts/unregister-mutation-run.ps1.
#
# Deliberately NOT shared with explorer-schedule.ps1 despite the near-
# identical shape: the two tasks landed hours apart for unrelated reasons,
# and a premature abstraction across them would couple two independent
# schedules for no present benefit (conductor instruction, task 110).

function Get-MutationScheduleCommandLine {
    param(
        [Parameter(Mandatory)][string]$PwshPath,
        [Parameter(Mandatory)][string]$ScriptPath
    )
    return '"{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}"' -f $PwshPath, $ScriptPath
}

function Get-MutationScheduleRegisterArgs {
    # /F makes registration idempotent -- re-running register-mutation-run.ps1
    # updates the existing task instead of erroring. /RL LIMITED: standard-user
    # rights, never elevated -- this only ever reads the repo and runs tests.
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$CommandLine,
        [Parameter(Mandatory)][string]$StartTime,
        [Parameter(Mandatory)][string]$DayOfWeek
    )
    return @('/Create', '/TN', $TaskName, '/TR', $CommandLine, '/SC', 'WEEKLY', '/D', $DayOfWeek, '/ST', $StartTime, '/RL', 'LIMITED', '/F')
}

function Get-MutationScheduleUnregisterArgs {
    param([Parameter(Mandatory)][string]$TaskName)
    return @('/Delete', '/TN', $TaskName, '/F')
}
