# Task 053 — The merge gate can attest a pass for a run that failed

## Status

agent: 053
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task053 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task053-ci-receipt-gate.
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

- Your inbox: `C:/git/decompile-sc/work/messages/053/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 053 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

A local CI receipt must never be able to attest a pass for a run that failed,
was never run, or tested something other than the sha it names. With GitHub
Actions dead on billing, `merge-task.ps1 -LocalCiReceipt` is the ENTIRE merge
gate for this repo — every merge tonight went through it. Close the three holes
in issue #72 and prove each one closed with a test that fails on today's code.

## Context

- **Issue: https://github.com/inwenis/decompile-sc/issues/72.** Found by task
  052, the first architectural review, and ranked its top finding — above every
  product bug — precisely because it is the thing that lets other bugs through.
- **Hole 1 is confirmed by the conductor's own measurement, not just read from
  the source.** `run-ci-local.ps1:127` calls `Invoke-Pester -Path tests -CI
  -PassThru`. Pester's `-CI` calls `exit` on a red run, which kills the whole
  `run-ci-local` process at that line — so the `throw` on the next line, the
  receipt write at `:251`, and the FAIL summary never execute. Measured on this
  machine with a deliberately-red fixture suite:

      Invoke-Pester -Path tests -CI -PassThru
      Write-Host "REACHED-AFTER-PESTER ..."     <- never printed
      child process exit code: 1

  The receipt path is deterministic (`"$branch-$sha.json"`), so a PASS receipt
  written by an earlier run at the same sha survives untouched and
  `merge-task.ps1` accepts it. A red run and a green run differ only in console
  output that nobody re-reads.
- **Hole 2: the receipt names a sha it did not necessarily test.** `:48-49`
  takes `git rev-parse --short HEAD` with no `git status --porcelain` check, so
  uncommitted edits are tested and attributed to the clean sha. And
  `lib/ci-local.ps1:71` matches with `$HeadSha.StartsWith($sha)` — no minimum
  prefix length, no freshness or provenance check on the file the caller names.
- **Hole 3: skips below the step level are invisible.** `:129` records only
  `PassedCount`. All ~19 cases in `tests/make-test-map.Tests.ps1` skip on a
  machine without python (`:52,95,147,172`), and the receipt then reads pass
  with a smaller number that nothing compares against. The `Skip-Step`
  classification itself (`:59-80`, a property sniff for `ScStepSkipped`) has
  ZERO test coverage and misses when a step body emits output before returning
  `Skip-Step`, because `$out` is then an array.
- **The repo's own rule applies to its own gate:** *"A SKIPPED GATE IS NOT A
  PASSED GATE"* is already written in `run-ci-local.ps1`'s own `.DESCRIPTION`
  (task 023). Hole 3 is that rule being broken one level below where it was
  enforced — the step is not skipped, the tests inside it are.
- The fixes issue #72 proposes, in its value order — take them as a starting
  point and say so if you disagree after reading the code:
  1. delete/invalidate the receipt for the current sha at run START, before any
     step runs, so a crashed run cannot leave a stale pass behind;
  2. drop `-CI` (keep `-PassThru`) so a red run reaches its own receipt write and
     records `fail` — the script already throws on `FailedCount`;
  3. record `SkippedCount` / `NotRunCount` / `FailedBlocksCount`, and refuse a
     pass when containers failed to discover;
  4. refuse or record a dirty worktree; require a minimum sha-prefix length in
     the validator;
  5. cover `Skip-Step` classification with a Pester test.
- **Do not silently widen the gate while fixing it.** If a change would make a
  currently-passing situation fail (e.g. refusing a dirty worktree), say so
  plainly — that is probably correct, but it is the conductor's call whether it
  lands tonight or behind a flag, because it affects every worker's flow.
- No game runs. Nothing here touches StarCraft; 048 owns the machine.

## Steps (suggested)

1. Reproduce hole 1 as a TEST first — a red Pester run must leave a `fail`
   receipt, and today it leaves the old pass. Write the test, watch it fail,
   then fix. That test is the deliverable as much as the fix is.
2. Then holes 2 and 3, each with its own failing-first test.
3. Re-read `merge-task.ps1`'s validator with the same eye: it is the consumer,
   and a receipt it accepts too loosely is the same defect one file over.

## Acceptance criteria

1. Each of the three holes has a test that FAILS on current `main` and passes
   after the change. Name them in the PR and say which line each pins.
2. A red Pester run produces a receipt whose verdict is `fail` — demonstrated,
   with the console transcript, not argued.
3. A receipt cannot be accepted for a sha it did not test: state exactly what
   "did not test" now means (dirty worktree, prefix too short, stale file) and
   which of those you enforce versus record.
4. Sub-step skips are visible in the receipt and in the printed summary.
5. `Skip-Step` classification has test coverage, including the array case where
   a step emits output before returning it.
6. `scripts/run-ci-local.ps1` PASS at your final sha, PR opened with the link in
   Status.pr. Cloud CI is down on billing — note it in the body. Yes, this task
   is gated on the thing it is fixing; run it and paste the console output, since
   the console is trustworthy even where the file is not.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/053-ci-receipt-gate.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
