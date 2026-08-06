# Task 006 — Fix CI red-on-green: stale LASTEXITCODE fails every run

## Status

agent: 006
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task006 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task006-ci-exit-code-fix.
- Task-file edits, reports, messages: directly in C:/git/decompile-sc (main
  checkout, no commits there — conductor commits; you are the only writer).
- NEVER edit tracked content in the main checkout.
- Destructive/irreversible actions beyond your own worktree (deleting user
  files, force-push, merging PRs, killing processes) → stop, ask in your tab
  or message the conductor first.
- NEVER delete/overwrite anything under C:/git/decompile-sc/work/messages/
  (2026-07-17 data-loss incident class — real user messages live there).
- C:/git/conductor and C:/git/conductor-task* are ANOTHER LIVE SYSTEM (a
  separate orchestrator with in-flight agents and real user messages).
  NEVER read, modify, cd into, or run git/gh against them — off-limits
  absolutely (guard hooks also enforce this). Your world is
  C:/git/decompile-sc and your own worktree only.

## Game-file rules (project hard rules)

- NEVER commit game binaries, MPQ archives, extracted assets, or anything
  derived from them that reproduces game content. The repo tracks findings
  and tooling only.
- The local game copy lives at an ignored path (game/) and is READ-ONLY to
  workers.
- Never point a modified binary at Battle.net or any online service. Offline
  and single-player only.
- Every claimed address/offset/struct must carry evidence: how it was found
  and how it was verified. No guessed offsets in research/.

## Messaging

- Your inbox: `C:/git/decompile-sc/work/messages/006/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 006 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

CI is red on **every single run**, including on `main`, for one reason that has nothing to do
with the code being checked. Fix it so `main` is green and the three open PRs can be merged.
This is the highest-priority task on the board — every merge is blocked behind it.

## Context

GitHub Actions is now working on this repo (it was blocked account-wide earlier; that is
resolved). All 8 runs so far completed with `failure`. Diagnosis, already done for you — the
failing step is **"Lint (ruff, only if pulled in via requirements.txt)"** in
`.github/workflows/ci.yml`:

```powershell
$ruffInstalled = $false
try {
    pip show ruff *> $null
    if ($LASTEXITCODE -eq 0) { $ruffInstalled = $true }
} catch {}
if ($ruffInstalled -and (Test-Path 'tools')) {
    ruff check tools
} else {
    Write-Host 'ruff not installed (or tools/ absent) -- skipping lint'
}
```

The run log shows it printing `ruff not installed (or tools/ absent) -- skipping lint`
followed immediately by `##[error]Process completed with exit code 1.` — i.e. the step took
the *correct* branch and then failed anyway.

Root cause: `pip show <missing-package>` exits **1**. That leaves `$LASTEXITCODE` at 1.
`Write-Host` does not reset it. GitHub's `pwsh` shell wrapper ends the step by exiting with
whatever `$LASTEXITCODE` holds, so the step fails *because the optional linter was correctly
skipped*. Evidence: run 31131552016, job log, step "Lint (ruff...)".

Note the irony worth internalising: this is the same class of bug as two earlier findings in
this repo — PowerShell exit-code and error-action semantics not matching the author's intent.
It is the dominant failure mode in this codebase's tooling. Keep that in mind while fixing.

## Hard rules

1. Do **not** weaken the checks to make CI pass. The parse check, JSON validation and
   game-content guard are the entire value of this workflow. Fixing means making the step
   report accurately, not deleting it.
2. Do **not** edit `scripts/merge-task.ps1` or `scripts/lib/merge-task.ps1`. The merge gate is
   correct.
3. Do **not** merge your own PR.
4. Keep the workflow hermetic — no game files, no Ghidra, no network beyond package installs.

## Steps (suggested)

1. Fix the ruff step so a missing (optional) ruff is a clean skip that leaves the step
   successful. Reset `$LASTEXITCODE` explicitly after the probe, or end the step with an
   explicit `exit 0` on the skip path — but make the *real* lint failure path still fail the
   step when ruff IS installed and reports problems. Both behaviours must be correct, not just
   the skip.
2. **Audit every other step in `ci.yml` for the same trap.** Any step whose last executed
   native command can leave a non-zero `$LASTEXITCODE` will fail the same way. Check the
   `pip install` step, the `compileall` step, and the game-content guard's `git ls-files`.
   Fix any you find. This is more valuable than fixing only the one that happens to be red
   today.
3. Consider whether ruff should simply be added to `requirements.txt` so the lint actually
   runs rather than being permanently skipped. Your call — if you add it, make sure the repo's
   existing `tools/*.py` actually passes, and if it does not, either fix the trivial lints or
   leave ruff out. Do not commit a red lint.
4. Push and **watch the run on your own PR go green**. Then report.

## Acceptance criteria

1. `.github/workflows/ci.yml` fixed; the run on this task's own PR is **green**. Paste the run
   URL and conclusion in the PR — do not report done off reasoning alone.
2. All other steps audited for the stale-`$LASTEXITCODE` trap, with a note in the PR saying
   what you checked and what you changed.
3. Checks still genuinely fail when they should: demonstrate that a deliberately broken `.ps1`
   still fails the parse step, and that the game-content guard still rejects a force-added
   binary. Prove it locally, revert, and do not commit anything broken.
4. No check weakened or removed. No merge-gate files touched.
5. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/006-ci-exit-code-fix.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
