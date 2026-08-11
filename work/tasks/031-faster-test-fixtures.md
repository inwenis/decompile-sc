# Task 031 — Make in-game suites faster with map-level unit settings

## Status

agent: 031
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/38
merged: 2026-08-11

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task031 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task031-faster-test-fixtures.
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

- Your inbox: `C:/git/decompile-sc/work/messages/031/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 031 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Make the in-game suites meaningfully faster by putting the right numbers in the FIXTURE
instead of waiting on vanilla ones.** User: "can you speed up tests by making custom maps with
units that build faster, have less hp, etc?" A suite currently costs ~4 minutes and there are
ten of them, run repeatedly, on one machine three workers share. Cutting that is worth real time
on every task after this one.

## Context

- **MEASURE BEFORE YOU OPTIMISE. This is the whole first half of the task.** Nobody knows where
  the four minutes actually go. Break one representative run down — launch + injection, menu
  walk, map load, fixture setup (units built/moved into position), the measurement itself,
  teardown — with numbers from the existing logs under `C:\sc-work\logs\` and a stopwatch pass if
  needed. Report the breakdown BEFORE changing anything. If build times turn out to be 5% of the
  run, the user's idea is not the win and you say so plainly — the menu walk and map load may
  well dominate, and that would point somewhere else entirely (a saved game? a shorter browser
  path? fewer relaunches per suite?). An honest "the idea does not help, here is what would" is a
  perfectly good outcome for this task.
- **The mechanism, if the numbers justify it: UNIS/UNIx, the map's own unit-settings override.**
  A Use Map Settings map can override per-unit hit points, shield points, armor, BUILD TIME,
  mineral cost, gas cost and base weapon damage. `tools/make_test_map.py` already does exactly
  this class of surgery for other sections — it parses the CHK into sections, replaces the few
  it must (`OWNR`, `SIDE`, `FORC`, `PTEx`), and writes the rest back BYTE FOR BYTE. Adding a
  UNIS/UNIx applier is the same shape as the existing `PTEx` applier; reuse it, do not invent a
  second style. Note the generator's own header comment: richchk 0.3.0 CORRUPTS UNIS/UNIx on a
  round-trip (4-18 bytes differ in the base-weapon-damage array on every map tried), which is
  why this tool does raw section surgery. Do not reintroduce a decode/re-encode path.
  - Establish which section the engine actually reads for a Brood War UMS map, UNIS or UNIx, and
    prove it — do not assume. The same "read it back from the ENGINE, not from the generator"
    rule that caught the PTEx index-order bug applies here (AGENTS.md, task 026): verify a
    changed build time by reading the running game, not by re-reading your own file.
- **The hazard, and it is the interesting part of this task: a faster fixture can INVALIDATE the
  measurement it speeds up.** Task 026 lost a run to exactly this — a target building died inside
  a two-second measurement window and every unit shooting it dropped to idle, which is
  bit-for-bit the signature the experiment was looking for. It then went the OTHER way
  deliberately, giving targets MORE hit points (Command Centres, 1500hp, instead of Supply
  Depots, 500) so a clean measurement became the normal case. So:
  - lower HP is dangerous precisely where a suite measures combat or liveness;
  - shorter build time is safe almost everywhere, because it is setup rather than measurement;
  - cheaper units are safe where a suite asserts on resources ONLY if the suite's own arithmetic
    is updated with it — `test-production-queue.ps1` asserts `2550 = 3000 - 9 x 50`.
  Go per-suite. A blanket "make everything fast and fragile" is a regression dressed as a speedup.
- **Every suite must still pass, and passing is not enough — it must still be able to FAIL.**
  For any suite you speed up, show its assertions still have teeth (AGENTS.md, absence assertions
  proved positive). Three of tonight's six caught defects were assertions that could not fail;
  a fixture change is a very easy way to create a fourth.
- **Concurrency:** tasks 028, 029 and 030 are live and all three use `make_test_map.py` and the
  in-game suites. You are editing shared test infrastructure they depend on — so: land the
  MEASUREMENT and the per-suite plan first and message me before changing any suite's fixture,
  and prefer additive, opt-in parameters (a suite asks for a fast fixture) over changing what the
  existing calls produce. Rebase before finishing; never kill another worker's game.
- Test discipline: own `Maps\BroodWar\00-t031\`, `Select-ScBrowserMap`, `New-ScFixtureRun`,
  `run-ci-local.ps1` (`ruff` NOT RUN is fine). `tests/make-test-map.Tests.ps1` exists (task 026) —
  extend it for whatever you add. GitHub Actions is billing-blocked; ignore it.

## Acceptance criteria

1. A time breakdown of one representative suite run, from evidence, with the phases named and
   their real durations — and a plain statement of which phases are worth attacking.
2. A stated verdict on the user's idea specifically: do faster build times / lower HP / cheaper
   units actually move the number, and by how much. "No" with evidence is an acceptable answer.
3. If yes: the UNIS/UNIx applier implemented in `make_test_map.py` in the existing raw-section
   style, with which section the engine reads PROVEN by reading a running game, not by re-reading
   the generated file.
4. A per-suite plan saying where each knob is safe and where it would confound the measurement,
   naming the suites that must NOT get lower HP and why.
5. At least one suite actually sped up end-to-end, with before/after wall-clock numbers — and its
   assertions shown to still be capable of failing.
6. No regressions: every in-game suite still 0 failures, hooktest green, `StarCraft.exe`
   byte-identical, no stranded processes, fixtures removed.
7. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/031-faster-test-fixtures.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
