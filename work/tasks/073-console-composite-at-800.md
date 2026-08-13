# Task 073 — Move the console PIXELS to the right edge, and let clicks reach them

## Status

agent: 073
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/111
merged: 2026-08-13

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task073 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task073-console-composite-at-800.
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

- Your inbox: `C:/git/decompile-sc/work/messages/073/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 073 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**At 800 wide the game still reads as "a 640 console sitting in the left of a
wide window."** Task 071 tried to move it, and produced a NO-GO with two named
blockers. You are the task that clears them.

Done means: the resource bar and command card are **drawn** at the window's right
edge, and **mouse clicks reach them there**. Both, or neither ships.

## Context

- **READ `research/renderer-viewport.md` §18 FIRST**, then
  `work/reports/071-console-at-800.md` and PR #110. §18 is a deliberate NO-GO
  write-up authored as your briefing. The prototype, the trace and the probe are
  in task 071's pre-split git history.
- **Task 071 shipped what worked and dropped what did not.** Its stage 3 (merged,
  #110) widens the engine's *input geometry* — 8 window-proc mouse clamps + 2
  mouse→world click-search-rect extents. **That is on main and is not your
  problem.** Your problem is the console.

### Blocker 1 — the bounds move but the pixels do not

**Task 071 moved `BinDlg` +0x04 and the engine's own dialog list reported the new
rects** — `StatRes (380,0)-(799,19)`, `StatBtn (656,354)-(799,479)`. **The
picture showed the console unchanged**: frame, MENU button and minimap all still
ending near x=648, and the resource number at its stock position near x=600
rather than near x=760 where a right-aligned 799 rect would put it.

- Capture: `C:\sc-work\logs\071-frames\console-800-ingame.png` (open it first).
- **So the console pixels have a SEPARATE position source** — the dialog surface
  composite in the layer-2 draw (`dlg+0x36` → screen), or the fixed-width console
  art, or both. Nobody has established which. **That is finding one.**
- 071 corrected its own §18.3 over-reading here: *"one rect, both consumers —
  drawing follows the bounds"* is **false**. Do not re-derive it.

### Blocker 2 — a stock router drops clicks at x>=640

Measured by 071 with every root dialog's `+0x2A` wrapped and named:

- A Train click at the card's new slot (682,374) produces **0 commands**, ring
  unchanged; same at (774,414) and at y>400.
- **The HOTKEY at the same instant trains fine** (ring 0→1) — so the card's
  action, buttonset and conditions are all correct at the new position. Only the
  mouse route fails.
- **The card's own interact is never invoked for any x>639 click**, while x<640
  clicks reach the console dialogs. The event-type handler table (`0x6D5E40`) is
  all-null, so the generic dispatcher is not short-circuiting.
- The card's own handling is sound — `0x00418EB0` → hit test `0x00418340`, both
  read LIVE bounds. **The drop is upstream, in a stock path that decides a
  console-region click belongs to the console and offers nothing at x>=640.**
  Written when the console was 640 wide.

**These are one job.** A console drawn at the edge that cannot be clicked is not
shippable, and a click router widened to nothing visible is untestable. Do not
split them.

### The oracle rules this task inherits — all three were learned the hard way today

1. **An oracle can be correct, authoritative, and about a different question than
   the one you are answering** (071, today). The dialog list is the right oracle
   for hit-test position and it does **not** settle where pixels are. **Any claim
   about what the user sees needs a window capture through cnc-ddraw.**
2. **Defect-era oracles** (068): an assertion calibrated while a bug was live
   encodes the bug. If an existing check fails on your build, ask whether it is
   asserting the old geometry first.
3. **Shim-era oracles** (070): WMode hides motion, not just columns; and **WMode
   crops x>=640, so it cannot show you the moved console at all.** Your visual
   arm must be cnc-ddraw. `probe-widescreen-drive.ps1` and
   `%SCDRIVE_POST_ACTIVATE%=1` (both merged, #108) are how off-screen input
   reaches it.
4. **Deselect before you assert a selection** (071, today): its "clicks past 640
   work" result came from a run where the unit was already selected, so the read
   never changed. Clean the slate first, every time.

### What must not break

1. The queue-indicator features and **cancel-by-click at every hold duration**
   (066, #102: 84/84 at 40-200ms). `test-production-queue.ps1` is the arm.
2. Minimap clicks steering the camera at 800.
3. **At 640 / flag off: byte-for-byte stock.** 071 verified this for stage 3 and
   you must keep it.
4. Stage 3's input widening — you build on it, you do not modify it without
   saying so.

### Constraints

- `StarCraft.exe` byte-identical; runtime patches only; off by default.
- **Run off-screen** (task 043). Never `C:\sc-deploy\starcraft-modded`, never the
  user's screen, never their display settings or registry.
- **Game frames NEVER go through `pr-image`** — hard rule 1. Paths travel.
- **Art is game content.** You may reposition or reuse what the engine loads; you
  may not commit extracted art or ship an asset file. **If the console can only
  sit at the edge by shipping art we cannot ship, that is a complete and
  acceptable answer** — say so with the evidence.

## Steps (suggested)

1. Open 071's capture. Then read §18 and find the composite path — where the
   console dialog surface is blitted to screen.
2. Prove the pixel-position source with ONE change and ONE capture before
   building anything on the theory.
3. Only then the click router.

## Acceptance criteria

1. **A cnc-ddraw window capture showing the resource bar at the top-right and the
   command card at the bottom-right** (path, not `pr-image`), with 071's capture
   as the before.
2. **A Train click at the card's new position issues the command** — measured on
   the wire, with the slate deselected first.
3. The must-not-break list above still passes, in a run you show me.
4. If either blocker proves structural: **the mechanism written at §18's
   standard**, and nothing half-shipped.
5. `scripts/run-ci-local.ps1` PASS **on a clean tree** — a receipt taken against
   a dirty worktree is refused by the gate, which cost 071 a round trip today.
6. PR opened with the link in Status.pr; cloud CI down on billing — note it.

## Stop-line

**Three honest attempts per blocker, then report.** Two tasks have now stopped on
this and both produced better work for it. **A measured "the console cannot move
because X" is a complete deliverable** — 071's is what made this task possible.

## Machine

The board is otherwise empty; the machine should be free. **Message the conductor
before your first launch anyway.**

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/073-console-composite-at-800.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
