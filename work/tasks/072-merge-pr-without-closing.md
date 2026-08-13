# Task 072 — Let a live task ship a hotfix PR without closing itself

## Status

agent: 072
model: sonnet
pr: https://github.com/inwenis/decompile-sc/pull/109
merged: 2026-08-13

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task072 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task072-merge-pr-without-closing.
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

- Your inbox: `C:/git/decompile-sc/work/messages/072/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 072 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**A worker that finds a regression on `main` while doing something else must be
able to ship the fix without closing its own task.** Today it cannot, and the
conductor had to break a standing rule to unblock the fleet.

## Context

- **Issue #107** carries the full account. Read it first.
- **What happened, 2026-08-13:** PR #105 shipped a strict-mode-unsafe `$global:`
  read in `sc-launch-lock.ps1`. Every suite dot-sources `drive-game.ps1`, which
  sets `Set-StrictMode -Version Latest`, so **every lock-taking suite on main
  broke**. Task 069 was already reaped. Task 070 hit it on a real run, had the
  fix, and opened **PR #106** — two lines plus a regression test that takes the
  lock the way a suite actually does.
- **There was then no supported way to merge it:**
  - `merge-task.ps1 -Task 070` merges whatever `pr:` names and then **stamps the
    task `merged:` and closes it** — while task 070's real work was still in
    flight;
  - `merge-task.ps1 -Task 070 -Pr 106` is not a thing. The argument binds to
    `ProgressAction` and dies with an enum error.
- **So the conductor ran `gh pr merge` by hand**, against the standing rule,
  having verified the receipt (`verdict: pass`, `sha e7a0c2e`, `dirty: False`,
  283 Pester including the new test). Main was broken for every worker meanwhile
  and task 071 had just started.
- **Why this matters more than the inconvenience.** The rule *"never `gh pr
  merge` by hand"* exists so the CI gate is never bypassed. Here the gate was
  satisfied and the tooling still could not express the operation, **so the rule
  had to be broken to do the right thing. A rule that must be broken for a
  legitimate case will be broken for illegitimate ones too.**
- **This is not exotic.** Any worker that finds a regression on main while doing
  something else lands in exactly this position, and today's fleet did it within
  four hours of the lock work landing.

### Directions, from the issue — pick one and say why

1. **A `-Pr` parameter that merges the named PR and does NOT stamp the task**,
   refusing unless the PR's head branch belongs to that task. The gate stays;
   only the bookkeeping is skipped.
2. **A separate `merge-pr.ps1`** for PRs with no task of their own, taking the
   same receipt gate.
3. Either way, the run should **say plainly that it merged a PR without closing a
   task**, so a board reader is not left wondering why an open task has a merged
   PR against it.

### Constraints

- **The CI gate is not negotiable.** Whatever you add takes the same
  `-LocalCiReceipt` path and the same refusals. This task makes an operation
  expressible; it does not make it looser.
- **Do not let the new path close or stamp a task**, ever. That is the whole bug.
- `merge-task.ps1` and `close-task.ps1` share `scripts/lib/`. Read both before
  changing either — task 069 (#105) touched `close-task` and `board-lint` an hour
  before this task was cut.
- **Board hygiene is derived, never written.** Status comes from the `merged:`
  stamp, the open PR and the registry. Nothing you add may write a status.

## Steps (suggested)

1. Read issue #107, then `merge-task.ps1` and `scripts/lib/close-task.ps1`.
2. Reproduce the failure: a branch belonging to task N whose PR is not task N's
   deliverable, and try to merge it. Both current paths fail — one wrongly
   succeeds at the wrong thing, one errors on parameter binding.
3. Implement, and prove the task it belongs to is **still open afterwards**.

## Acceptance criteria

1. **A hotfix PR from a live task merges, gated on its receipt, and the task
   stays open** — demonstrated with a test, not argued.
2. **The refusal cases hold**: a PR whose head branch does not belong to the
   named task is refused; a missing or failing receipt is refused; the existing
   `merge-task` behaviour for a task's own deliverable PR is unchanged.
3. The output says explicitly that a task was not closed.
4. A test that **fails without the change** — today's shape is "the tooling
   silently does the wrong thing", so a happy-path test proves nothing.
5. Issue #107 closed or updated with what was done.
6. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it in the body.

## Machine

**You do not need the game.** Task 071 is using it and has priority. If you think
you need it, message the conductor first.

Your worktree gets `.venv` provisioning from #105 now; if anything still
complains about `richchk`, junction the main checkout's `.venv` and say so —
that would mean #97 is not fully closed.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/072-merge-pr-without-closing.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
