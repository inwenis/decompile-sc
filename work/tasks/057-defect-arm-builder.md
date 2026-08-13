# Task 057 — Make a falsifiable oracle cheap: promote the throwaway defect arm into a script

## Status

agent: 057
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task057 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task057-defect-arm-builder.
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

- Your inbox: `C:/git/decompile-sc/work/messages/057/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 057 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Make watching an assertion FAIL cost about three minutes instead of a task.
Build `tools/plugin/build-defect-arm.ps1`: apply a patch that introduces a
deliberate defect to a throwaway copy of the plugin, build it, run hooktest on
both arms, and **print the checks whose verdict CHANGED**. That last step is the
whole deliverable — it is the only thing that distinguishes an oracle from a
line that reads green.

## Context

- **Issue: https://github.com/inwenis/decompile-sc/issues/78.** Read it in full;
  it carries the sizing, the five steps, and the cost table. This file does not
  repeat them.
- **Why this task exists rather than another bug fix.** Task 052's architectural
  review found "checks that cannot fail" to be this repo's dominant defect class
  and argued it is structural. Task 055 then spent a day repairing about fifteen
  of them and concluded ONE of 052's four causes is upstream of the rest:
  **a falsifiable oracle costs a task while a vacuous one costs a line.** Nobody
  writes `$x -eq $x` on purpose; they write it because the honest version needs a
  reading nothing captured yet, and capturing it means a four-minute game launch
  on a single-instance machine. This task attacks that price directly.
- **A working draft already exists** at `work/scratch/055-defect/make-defect-arm.ps1`
  — gitignored, written for issue #66 and thrown away, which is the problem in
  miniature. Generalise it and give it a home. Do not start from scratch without
  reading it.
- **It has already paid for itself once.** #66's decision to DELETE five stat
  counters rather than wire them stopped being an opinion when 055 built a defect
  arm with a real spend and measured: **28 balance checks failed while every
  single `spent NOTHING` check still read 0 and PASSED.** That is the output
  shape this script must make routine.
- **Scope limit, stated in the issue and worth repeating:** this reaches the C++
  oracles hooktest can reach. It does NOT cover the PowerShell in-game suites —
  those need the other, smaller thing (issue #81, golden-line tests for the
  printf→regex seam). Do not let this grow into a general test framework. If you
  find yourself designing one, stop and say so.
- **`hooktest` already does the hard part** — it links the real plugin sources
  and runs with no game. `build.ps1 -Test` is the existing entry point. The new
  script is orchestration around tools that work, not new machinery.
- **This is a hobby project.** ~40 lines is the target. A script somebody reads
  once and understands beats a configurable one.

## Steps (suggested)

1. Read the draft and `build.ps1`'s `-Test` path before writing anything.
2. Get the copy-and-build working first, into its own out-dir, with the real
   tree provably untouched — that is the one thing that must never go wrong.
3. Then the both-arms comparison, then the changed-verdicts report.
4. Then prove it on a defect you did not write: pick an assertion that is
   currently believed good, break the code under it, and see whether the check
   catches it. If it does not, you have found something and should say so.

## Acceptance criteria

1. The script runs end to end from a patch file and prints the changed-verdict
   list. Show its output in the PR for at least two different defects.
2. **The real tree is provably untouched** — demonstrated, e.g. `git status`
   clean and a hash of `tools/plugin/src` before and after. This script exists
   to break things; it must break them somewhere else. (Task 056 shipped a gate
   that would have rebuilt into a caller's named `-BuildDir`, including the
   user's deployed plugin, and caught it only on review. Same family.)
3. At least one defect where some checks catch it and some do not, with both
   lists printed. A run where everything catches everything proves nothing about
   the reporting.
4. Committed defect patches live somewhere sensible (`work/defects/` or similar)
   so the next author starts from examples rather than a blank file.
5. A short note in the PR on what this cannot reach — the in-game suites — with
   a pointer to #81, so nobody mistakes it for full coverage.
6. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it. **Merge `origin/main` before your final
   receipt**; the tree has moved four times tonight.

## Machine

No game runs required — hooktest needs no StarCraft. Task 054 is using the
machine; if you somehow need it, message the conductor rather than launching.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/057-defect-arm-builder.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
