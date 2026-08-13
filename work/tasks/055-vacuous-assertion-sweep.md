# Task 055 — The vacuous-assertion sweep: checks that pass by construction

## Status

agent: 055
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/77
merged: 2026-08-13

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task055 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task055-vacuous-assertion-sweep.
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

- Your inbox: `C:/git/decompile-sc/work/messages/055/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 055 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Kill the known checks that cannot fail, and — the part that matters more —
answer why they keep appearing. Four issues (#66, #68, #69, #70) plus one
mechanical regression (#71). Each fix must be proved by making the assertion
FAIL first on a build or fixture where the thing it claims is actually false;
an assertion "fixed" without ever being seen to fail has just been rewritten,
not repaired.

## Context

- **These came from task 052, the first architectural review**, which found this
  to be the repo's dominant defect class and — more usefully — argued it is
  STRUCTURAL, not five unlucky authors. Read `work/reports/052-architecture-review.md`
  § 4 before you start; the structural argument is the part this task exists to
  act on.
- **Read each issue in full; this file does not repeat their line numbers.**
  - **#71** — six raw `Set-Content` marker writes bypassing `Set-ScMarker`, a
    regression of the measured #37 finding (`Set-Content` opens the marker
    `FileShare.None` and therefore throws *with certainty* when the observer
    holds it open). Mechanical. **Do this one first** — it is six replacements
    plus a guard test, and it puts you inside the files the rest of the task
    lives in.
  - **#66** — five plugin stat counters printed and asserted `== 0` that
    nothing ever increments. Carries the money-conservation claim. **This one
    needs a decision, not just a fix:** wire them to the actual resource writes,
    or delete the counters AND the eight hooktest sites plus four suite
    assertions that lean on them. A counter that cannot count is worse than
    none. State which you chose and why.
  - **#68** — `test-random-conformance` can print `episodes run: 6 of 6` and
    PASS with every episode having skipped before acting; its seam counter
    counts intent rather than reach; and `-Profile upgrades` / `-Profile hudrow`
    dispatch to the wrong episode kind, so a green `-Profile upgrades` run
    exercises none of `sc_upgrades`. That last one is the worst of the five,
    because it is a green run that tests something other than what it says.
  - **#69** — a literal `x -eq x`, plus a cancel arm asserted purely from the
    plugin's own bookkeeping with no wire evidence.
  - **#70** — vacuous arms in three suites, all of the issue #45 shape: a
    negative never intersected with its positive, comparisons that pass when
    both sides are no-ops, a single sample where min-over-samples is required.
- **The oracle rule this task enforces on itself:** for every assertion you
  change, show it failing. Where a defect build is needed, task 048's shape is
  the model — build the pre-fix plugin into its own `-BuildDir` and run the same
  suite both ways. Where a fixture can make the claim false instead, prefer that;
  it is cheaper and it does not depend on a build.
- **Do not simply delete a weak assertion to make the count go down.** Every one
  of these was written because somebody cared about the claim underneath it. The
  claim is usually right and the oracle is wrong. Removing an assertion is
  allowed only when the claim itself turns out to be untestable here — and then
  say so, plainly, in the PR.
- **The structural question, which is a deliverable and not a footnote.** 052's
  answer: a `printf`→regex oracle seam with no contract (three drifted `HUDROW`
  parsers), no shared verdict machinery (25 copies of `Assert-That`, only 2 of
  18 suites can report INCONCLUSIVE), and — the core of it — **a falsifiable
  oracle costs a task while a vacuous one costs a line**. You are not expected
  to fix that architecture in this task. You ARE expected to propose the
  smallest change that would make the honest check the cheap one, having just
  spent a day inside the problem. One page, in the PR.
- **This is a hobby project.** Prefer the small fix that closes the hole to the
  general framework that would have prevented it. If a fix is growing, stop,
  land what works, and open an issue for the rest.
- **Machine sharing:** task 054 is running and needs the game for its own
  verification. `sc-launch-lock.ps1` serialises ONE launch, not a chain
  (issue #60), so a waiter can break the run it is waiting for. **Message the
  conductor BEFORE your first launch** and I will sequence you; do not queue
  into someone else's chain.

## Steps (suggested)

1. #71 first — mechanical, and add the guard test the issue suggests so a
   seventh copy cannot land.
2. Then #69 and #70, which are local and need no plugin change.
3. Then #66's decision, then #68, which is the largest.
4. Write the structural page last, when you have the evidence for it.

## Acceptance criteria

1. Every fixed assertion is shown FAILING before it is shown passing — the
   transcript of the failing run, or the defect-arm build that produced it,
   named in the PR. No exceptions: this task is about checks that cannot fail,
   so a fix nobody watched fail is the same defect.
2. #66's decision stated and carried out consistently — if the counters go, all
   eight hooktest sites and four suite assertions go with them; if they stay,
   they count something.
3. `-Profile upgrades` and `-Profile hudrow` either run their own episode kinds
   or refuse to run at all. A profile that silently tests something else must
   not be reachable.
4. A count of what reached each comparison is printed and gates the verdict,
   wherever a comparison can be skipped (#68's episodes, #70's sunken arms and
   samples).
5. One page in the PR on the structural cause and the smallest change that would
   make a falsifiable oracle the cheap default.
6. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it in the body. Task 053 is fixing the receipt
   gate itself; if it has landed when you finish, rebase onto it.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/055-vacuous-assertion-sweep.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
