# Pure helpers for scripts/run-mutation-check.ps1 -- turning a parsed Stryker
# mutation.json report into a summary, comparing two summaries for a
# regression, and formatting the conductor message. No filesystem, no
# Stryker/npm invocation, so tests exercise this against fabricated report
# objects (task 110, report 086 recommendation #4's alerting half).
#
# Score formula (Stryker's own convention, confirmed against report 086's
# measured numbers: 135 killed / (135 killed + 17 survived + 2 noCov) =
# 87.66%, matching the audit exactly):
#   detected   = Killed + Timeout        (a timeout is a killed mutant)
#   undetected = Survived + NoCoverage   (uncovered code is as bad as untested)
#   score      = detected / (detected + undetected) * 100
# Ignored/CompileError/RuntimeError mutants are excluded from both sides --
# they say something about test infra, not about assertion quality.

function Get-MutationTolerancePoints {
    # 0.5 percentage points. Justification (task 110): at the current
    # ~1122-mutant baseline, 0.5pp is worth ~5-6 mutants -- enough to absorb
    # the run-to-run coverage-analysis noise report 086 measured (a "no
    # coverage" bucket whose size can shift by a mutant or two between runs
    # with no code change), not enough to hide a real newly-survived mutant
    # on a small/medium file. Same constant is used for the overall score and
    # every per-file score so there is one number to tune, not several.
    return 0.5
}

function ConvertTo-MutationSummary {
    param([Parameter(Mandatory)]$Report)

    $totalKilled = 0; $totalSurvived = 0; $totalNoCoverage = 0; $totalTimeout = 0
    $files = @()

    foreach ($prop in $Report.files.PSObject.Properties) {
        $path = $prop.Name
        $killed = 0; $survived = 0; $noCoverage = 0; $timeout = 0
        $undetected = @()

        foreach ($mutant in @($prop.Value.mutants)) {
            switch ($mutant.status) {
                'Killed' { $killed++ }
                'Timeout' { $timeout++ }
                'Survived' {
                    $survived++
                    $undetected += [PSCustomObject]@{
                        line        = $mutant.location.start.line
                        column      = $mutant.location.start.column
                        mutatorName = $mutant.mutatorName
                        status      = $mutant.status
                        key         = "$($mutant.location.start.line):$($mutant.location.start.column):$($mutant.mutatorName)"
                    }
                }
                'NoCoverage' {
                    $noCoverage++
                    $undetected += [PSCustomObject]@{
                        line        = $mutant.location.start.line
                        column      = $mutant.location.start.column
                        mutatorName = $mutant.mutatorName
                        status      = $mutant.status
                        key         = "$($mutant.location.start.line):$($mutant.location.start.column):$($mutant.mutatorName)"
                    }
                }
                default { } # Ignored/CompileError/RuntimeError/Pending -- excluded from scoring
            }
        }

        $totalKilled += $killed
        $totalSurvived += $survived
        $totalNoCoverage += $noCoverage
        $totalTimeout += $timeout

        $files += [PSCustomObject]@{
            path              = $path
            score             = Get-MutationScoreFraction -Killed $killed -Timeout $timeout -Survived $survived -NoCoverage $noCoverage
            killed            = $killed
            survived          = $survived
            noCoverage        = $noCoverage
            timeout           = $timeout
            undetectedMutants = @($undetected)
        }
    }

    [PSCustomObject]@{
        overallScore = Get-MutationScoreFraction -Killed $totalKilled -Timeout $totalTimeout -Survived $totalSurvived -NoCoverage $totalNoCoverage
        totals       = @{ killed = $totalKilled; survived = $totalSurvived; noCoverage = $totalNoCoverage; timeout = $totalTimeout }
        files        = @($files)
    }
}

function Get-MutationScoreFraction {
    param([int]$Killed, [int]$Timeout, [int]$Survived, [int]$NoCoverage)
    $detected = $Killed + $Timeout
    $valid = $detected + $Survived + $NoCoverage
    if ($valid -eq 0) { return 100.0 }
    return [math]::Round(($detected / $valid) * 100, 2)
}

function Compare-MutationSummary {
    param(
        [Parameter(Mandatory)]$Baseline,
        [Parameter(Mandatory)]$Current,
        [double]$ToleranceP = (Get-MutationTolerancePoints)
    )

    $baselineByPath = @{}
    foreach ($f in @($Baseline.files)) { $baselineByPath[$f.path] = $f }

    $regressedFiles = @()
    foreach ($f in @($Current.files)) {
        if (-not $baselineByPath.ContainsKey($f.path)) { continue } # new file, nothing to regress against
        $base = $baselineByPath[$f.path]
        $delta = [math]::Round($base.score - $f.score, 2)
        if ($delta -le $ToleranceP) { continue }

        $baseKeys = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($m in @($base.undetectedMutants)) { [void]$baseKeys.Add($m.key) }
        $newlyUndetected = @($f.undetectedMutants | Where-Object { -not $baseKeys.Contains($_.key) })

        $regressedFiles += [PSCustomObject]@{
            File            = $f.path
            BaselineScore   = $base.score
            CurrentScore    = $f.score
            Delta           = $delta
            NewlyUndetected = $newlyUndetected
        }
    }

    $overallDelta = [math]::Round($Baseline.overallScore - $Current.overallScore, 2)
    $regressed = ($overallDelta -gt $ToleranceP) -or ($regressedFiles.Count -gt 0)

    [PSCustomObject]@{
        Regressed            = $regressed
        OverallBaselineScore = $Baseline.overallScore
        OverallCurrentScore  = $Current.overallScore
        OverallDelta         = $overallDelta
        RegressedFiles       = @($regressedFiles | Sort-Object -Property Delta -Descending)
    }
}

function Format-MutationRegressionMessage {
    param(
        [Parameter(Mandatory)]$Comparison,
        [Parameter(Mandatory)][string]$HtmlReportPath
    )

    $lines = @()
    $lines += "1. Overall score: $($Comparison.OverallBaselineScore)% -> $($Comparison.OverallCurrentScore)% (dropped $($Comparison.OverallDelta) pp, tolerance $(Get-MutationTolerancePoints) pp)."
    $lines += "2. Regressed file(s):"
    $i = 0
    foreach ($rf in $Comparison.RegressedFiles) {
        $i++
        $lines += "   $i. ``$($rf.File)`` — $($rf.BaselineScore)% -> $($rf.CurrentScore)% (dropped $($rf.Delta) pp)"
        foreach ($m in $rf.NewlyUndetected) {
            $lines += "      - newly $($m.status.ToLowerInvariant()): ``$($rf.File):$($m.line)`` ($($m.mutatorName))"
        }
    }
    $lines += "3. Full report: ``$HtmlReportPath``."
    $lines += "4. What this measures: whether src/core tests assert behaviour or just execute it. It does not catch concurrency/interleaving bugs (see report 086)."
    return ($lines -join "`n")
}
