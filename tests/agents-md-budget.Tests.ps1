#Requires -Version 7
<#
AGENTS.md is loaded into every agent turn. Between 2026-08-06 and 2026-08-13 it grew from
166 to 1229 lines by append-only incident journalling; the rules it carried were restated
up to four times, buried 40-100 lines into stories, and contradicted by later appends.
The file was rebuilt as a short topic-ordered rulebook (research/rulebook-history.md holds
the old text). These checks keep it that way:

  1. line budget (300)
  2. no dates or task ids in headings (incident journalling goes in the PR, not here)
  3. no vocabulary from the removed orchestration layer
  4. every `research/rulebook-history.md § "..."` pointer names a heading that exists

The positive control runs the same checks against the archive, which must FAIL them --
otherwise this file is not testing anything (AGENTS.md: an absence assertion is worth
nothing until the pattern has been shown to match somewhere it should).
#>

BeforeAll {
    $script:root    = Join-Path $PSScriptRoot '..'
    $script:rules   = Join-Path $root 'AGENTS.md'
    $script:archive = Join-Path $root 'research' 'rulebook-history.md'
    $script:budget  = 300

    function Get-AgentsMdViolations {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ArchivePath)
        $v = [System.Collections.Generic.List[string]]::new()
        # A missing file must be a violation, not an empty list -- Get-Content's
        # non-terminating error left $lines null and this test green once already.
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { $v.Add("missing: $Path"); return $v }
        $lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop)

        if ($lines.Count -gt $script:budget) { $v.Add("length: $($lines.Count) lines > $script:budget") }

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $l = $lines[$i]; $n = $i + 1
            if ($l -match '^#{1,6}\s' -and $l -match '\d{4}-\d{2}-\d{2}|\btask \d{3}\b') {
                $v.Add("dated heading: L$n $l")
            }
            if ($l -match '\b(conductor|workers?|heartbeat|residue)\b|\btask file\b') {
                $v.Add("orchestration-era vocabulary: L$n $l")
            }
        }

        $headings = (Get-Content -LiteralPath $ArchivePath) |
            Where-Object { $_ -match '^#{1,6}\s' } |
            ForEach-Object { ($_ -replace '^#+\s*', '').Trim() }
        $text = $lines -join "`n"
        foreach ($m in [regex]::Matches($text, 'rulebook-history\.md\s*§\s*"([^"]+)"')) {
            $want = $m.Groups[1].Value.Trim()
            $hit = $headings | Where-Object { $_.StartsWith($want, [StringComparison]::OrdinalIgnoreCase) -or $_.Contains($want, [StringComparison]::OrdinalIgnoreCase) }
            if (-not $hit) { $v.Add("dangling pointer: § `"$want`" matches no heading in research/rulebook-history.md") }
        }
        return $v
    }
}

Describe 'AGENTS.md stays a short rulebook' {
    It 'positive control: the archived journal FAILS these checks' {
        $v = Get-AgentsMdViolations -Path $archive -ArchivePath $archive
        ($v | Where-Object { $_ -like 'length:*' }) | Should -Not -BeNullOrEmpty
        ($v | Where-Object { $_ -like 'dated heading:*' }) | Should -Not -BeNullOrEmpty
        ($v | Where-Object { $_ -like 'orchestration-era vocabulary:*' }) | Should -Not -BeNullOrEmpty
    }

    It 'AGENTS.md passes every check' {
        $v = Get-AgentsMdViolations -Path $rules -ArchivePath $archive
        ($v -join "`n") | Should -BeNullOrEmpty
    }
}
