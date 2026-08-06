# Pure/testable helpers for new-task.ps1 -- cut + worktree + spawn in one
# command (task 060, report 055 PROPOSAL 2). No git/gh/process work lives
# here -- those side effects stay in scripts/new-task.ps1 so this file can be
# dot-sourced straight into Pester and exercised on strings and temp dirs.
# See tests/new-task.Tests.ps1.

function Get-TaskIdsInDir {
    # 3-digit ids of every tasks/NNN-*.md file in a dir (excludes _template.md
    # and anything without a leading 3-digit id). Real filesystem scan, but no
    # git/gh -- tested against a disposable temp dir.
    param([Parameter(Mandatory)][string]$TasksDir)
    if (-not (Test-Path -LiteralPath $TasksDir)) { return @() }
    Get-ChildItem -LiteralPath $TasksDir -Filter '*.md' -File |
        ForEach-Object {
            $m = [regex]::Match($_.Name, '^(\d{3})-')
            if ($m.Success) { $m.Groups[1].Value }
        }
}

function Get-NextTaskId {
    # Next free 3-digit task id: always one past the highest id ever used, so
    # a gap left by a cancelled/renumbered task is never reused. Throws when
    # the 3-digit space is exhausted (999 -> 1000 doesn't fit the id format).
    param([string[]]$ExistingIds = @())
    $max = 0
    foreach ($id in $ExistingIds) {
        $n = [int]$id
        if ($n -gt $max) { $max = $n }
    }
    if ($max -ge 999) {
        throw "Get-NextTaskId: 3-digit task id space exhausted (highest used: $max) -- extend the id format."
    }
    return '{0:D3}' -f ($max + 1)
}

function Test-ValidSlug {
    # Slugs become directory and branch-name fragments (taskNNN-<slug>) --
    # keep them to the shape every other script already assumes.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Slug)
    # -cmatch: PowerShell's plain -match is case-insensitive, which would
    # wrongly accept 'New-Task' as a lowercase-kebab slug.
    return $Slug -cmatch '^[a-z0-9]+(-[a-z0-9]+)*$'
}

function ConvertTo-TitleFromSlug {
    # Fallback title when -Title is omitted: 'new-task-script' -> 'New Task Script'.
    param([Parameter(Mandatory)][string]$Slug)
    $words = $Slug -split '-' | Where-Object { $_ }
    return ($words | ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }) -join ' '
}

function New-TaskFileContent {
    # Fill every substitutable field in the _template.md text; leave Goal/
    # Context as clearly-marked TODO(conductor) blocks. Pure string
    # transform -- no file I/O, no knowledge of where the template lives.
    param(
        [Parameter(Mandatory)][string]$TemplateContent,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$Slug,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Model
    )
    # [^\r\n]* (not .*) so a CRLF line's trailing \r is never swallowed into
    # the match and dropped by the replacement -- the template is CRLF
    # throughout and a stray bare-LF line would corrupt that silently.
    $out = $TemplateContent -replace 'NNN', $TaskId
    $out = $out -replace '<slug>', $Slug
    $out = $out -replace '<title>', $Title
    $out = $out -replace '(?m)^agent:[^\r\n]*', "agent: $TaskId"
    $out = $out -replace '(?m)^model:[^\r\n]*', "model: $Model"
    # Goal/Context placeholders stay visible (the conductor still needs the
    # hint text) but get a TODO(conductor) marker prepended so a half-cut
    # task is unmistakable at a glance.
    $out = $out -replace '(?m)^(<what must be true[^\r\n]*)', 'TODO(conductor): $1'
    $out = $out -replace '(?m)^- (<pointers:[^\r\n]*)', '- TODO(conductor): $1'
    return $out
}

function Get-TaskModel {
    # pull the `model:` value out of a task file's Status block
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    $m = [regex]::Match($Content, '(?m)^model:\s*(\S+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-FetchArgs {
    param([Parameter(Mandatory)][string]$Repo)
    return @('-C', $Repo, 'fetch', 'origin', '--quiet')
}

function Get-WorktreeAddArgs {
    # FRESH REMOTE base (2026-07-17 stale-base lesson): always branches off
    # origin/main, never local main.
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$Slug
    )
    $worktreePath = "$Repo-task$TaskId"
    $branch = "task$TaskId-$Slug"
    return @('-C', $Repo, 'worktree', 'add', $worktreePath, '-b', $branch, 'origin/main')
}

function New-CutCommitMessage {
    # matches existing history style: "chore(tasks): cut task NNN (<slug>)"
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$Slug
    )
    return "chore(tasks): cut task $TaskId ($Slug)"
}
