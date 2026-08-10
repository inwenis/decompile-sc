# Task 028 — Prove production cancel-refund in a real game

## Status

agent: 028
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task028 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task028-production-cancel-refund.
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

- Your inbox: `C:/git/decompile-sc/work/messages/028/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 028 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Cancel a queued unit in a real game and prove the refund is right — including an item the
PLUGIN is holding, not just one in the engine's ring.** The user asked directly: "why is there
no test that cancels a unit?" Task 025 shipped the >5 queue with cancel proved only OFFLINE
(byte-exact both directions, plus the handler disassembly). Nothing has ever clicked cancel in
a running game. Close that (GitHub issue #26).

## Context

- **The thing that blocked this is gone.** Issue #26 was deferred because the cancel control's
  rect could not be read from memory, and guessing pixel coordinates is forbidden
  (AGENTS.md "Read a dialog's CONTENT from memory; never hash its pixels"). Task 026 merged the
  card reader on 2026-08-09: `tools/plugin/src/sc_card.cpp` + `sc_card.h`, launched with
  `-CardScan 1`, and PowerShell-side `Get-ScCardState` / `Get-ScCardSlot` /
  **`Get-ScCardSlotPoint`** in `tools/plugin/drive-game.ps1` (~line 1828+). `Get-ScCardSlotPoint`
  computes a clickable point from the live dialog — that is exactly the primitive #26 was
  waiting for.
- **Do NOT assume the cancel control is on the command card.** In vanilla StarCraft you cancel a
  queued unit by clicking its icon in the PRODUCTION QUEUE strip in the status pane, not by a
  Cancel button on the command card. `research/hud-selection-row.md` + `sc_hudrow.cpp` are the
  prior art for the status-pane dialog; `research/command-card.md` (task 026) is the prior art
  for the card. FIND which dialog actually owns the queue icons and read its control rects —
  do not guess, and do not port `Get-ScCardSlotPoint` blindly if the control lives elsewhere.
  If it turns out the status pane needs the same treatment the card got, that is the real work
  of this task; say so and keep it minimal.
- **The interesting half is the PLUGIN's own refund path, and it is the one never exercised.**
  `sc_prodqueue.cpp` (task 025) keeps the engine ring at `SC_PRODQ_ENGINE_HOLD` (4) and holds
  the overflow itself. So there are TWO cancel cases and they take different code:
  1. cancelling an item inside the engine's ring — the engine refunds, plugin must not
     double-refund and must not lose its promotion order;
  2. cancelling an item the PLUGIN holds — `SC_PRODQ_STAT_CANCELLED` and the plugin's own
     refund write, which is the plugin's ONLY resource write anywhere.
  Case 2 is the one with real money risk and zero in-game evidence. Cover both; if the UI cannot
  address an overflow item at all (it may only draw 5), that is itself a finding — report it,
  and say what the player actually sees and can click.
- **Watch the wire first, before trusting any handler reasoning.** AGENTS.md, from task 025:
  a player-input feature is unproven until the engine's command funnel (`queueCommand`
  0x00485BD0) has been watched in a real game. That rule exists *because* 025's first design was
  inert. Confirm a cancel click actually emits a command before asserting anything about refunds.
- Read the numbers from MEMORY, never the UI: queue length from the building's own `CUnit+0x98`,
  minerals from the resource global. `test-production-queue.ps1` (merged) already does both and
  is the suite to extend — extend it, do not fork it.
- Test discipline: your own `Maps\BroodWar\00-t028\`, `Select-ScBrowserMap`, `New-ScFixtureRun`,
  the shared launch lock. `run-ci-local.ps1` for the offline gate (`ruff` will report NOT RUN —
  optional, does not block). GitHub Actions is billing-blocked repo-wide; ignore it.
- The harness no longer raises the game window (task 027). Run `watch-foreground.ps1` alongside
  and report what it saw. You are the only task running, so the machine is yours.

## Acceptance criteria

1. The cancel control located by READING the owning dialog from memory — which dialog, which
   control, how the rect is computed. Addresses carry how-found + how-verified.
2. A cancel click shown to reach the engine's command funnel before any refund claim is made.
3. In-game, unattended: cancel an item in the ENGINE ring — queue length drops by one (read from
   the building's memory) and minerals go up by exactly that unit's cost, asserted per-item.
4. In-game, unattended: cancel an item the PLUGIN holds — same two assertions, plus the plugin
   refunds exactly once. If the UI cannot address an overflow item, state that with evidence and
   say what the player sees instead.
5. No double-refund and no lost item in either case: the totals reconcile (`spent = built +
   queued + cancelled`), asserted from memory rather than narrated.
6. `test-production-queue.ps1` extended (not forked); existing in-game suites + hooktest green;
   `StarCraft.exe` byte-identical; no stranded processes; fixture removed.
7. PR opened, link in Status.pr. Issue #26 referenced so it closes on merge.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/028-production-cancel-refund.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
