# Task 071 — Move the console to the right edge at 800 wide

## Status

agent: 071
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/110
merged: 2026-08-13

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task071 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task071-console-at-800.
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

- Your inbox: `C:/git/decompile-sc/work/messages/071/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 071 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**At 800 wide the game currently reads as "a 640 console sitting in the left of
a wide window".** The map is wide and correct; the HUD is not where a player
expects it. Resources are not at the window's top-right, the command card is not
at its bottom-right, and there is a bare strip at `640..799 × 400..479` with no
console art in it.

Make the console belong to the 800-wide window: resource bar to the right edge,
command card to the bottom-right, and the dead strip gone or deliberately
filled. **Nothing that works today may stop working.**

## Context

- **This is the last thing between the user's goal and something they would
  actually enjoy looking at.** The functional work is done and merged: stage 2
  (#99), fog (#104), presentation (#98), and 070's assembled build reproduces
  all of it. The map is genuinely wider and correctly fogged.
- **Task 070 scoped this out deliberately and it was right to** — *"moving the
  console right would be its own task (dialog init positions + art)"*. You are
  that task. **Read 070's PR and card before anything else**; it is your
  briefing and it carries the driven-session findings.

### 070's measurements — the engine's own dialog rects, presentation-independent

| element | rect | note |
|---|---|---|
| Minimap | `(0,315)-(137,479)` | stock bottom-LEFT corner; **clicks already steer the camera at 800** |
| Command card `StatBtn` | `(496,354)-(639,479)` | ends at x=639, not flush right |
| Resource bar `StatRes` | `(220,0)-(639,19)` | ends at x=639 |
| dead strip | `640..799 × 400..479` | no console art; the one thing that looks broken |

- **Nothing of the console extends into x=640..799 today**, and nothing overlaps
  the new map area. So this is a move, not a rescue.
- The console dialogs live in **their own surfaces**, not the main framebuffer
  (`research/renderer-viewport.md` §2 correction). `sc_queueind.cpp` already
  reads and draws into those surfaces — tasks 039/048/066 built their whole
  feature on it. **That is your precedent for touching them.**
- The dead strip is §15.5 in the research doc.

### What must not break — the list is specific and all of it is measured

1. **The queue indicator features** — the `+N` overflow, the fifth slot, the
   group queue line, and **cancel-by-click at every hold duration** (task 066,
   PR #102: 84/84 at 40-200ms). `test-production-queue.ps1` is the arm.
2. **Minimap clicks steering the camera**, proven at 800 by 068 and 070.
3. **The >12-unit paging row** and building groups (tasks 048, #44).
4. **Mouse hit-testing.** If you move a control, clicks must follow it. This is
   the most likely thing to break and the hardest to notice in a still frame.

### Constraints

- `StarCraft.exe` on disk byte-identical (runtime patches only); everything
  behind the existing off-by-default flag; never write the user's display
  settings, desktop layout, or registry.
- **Run off-screen** (task 043). **Do NOT touch `C:\sc-deploy\starcraft-modded`**
  or run anything on the user's screen.
- **Game frames NEVER go through `pr-image`** — hard rule 1. Paths travel.
- **Art is game content.** If filling the dead strip needs artwork, you may
  reposition or reuse what the engine already loads; you may **not** commit
  extracted art, and you may not ship a new asset file. If the honest answer is
  "the strip can only be filled with art we cannot ship", say so and leave it
  black — a clean black strip is an acceptable outcome.

### Traps paid for by other tasks today — do not re-learn these

- **Defect-era oracles** (AGENTS.md, task 068): an assertion calibrated while a
  bug was live encodes the bug. If an existing check fails on your build, ask
  whether it is asserting the old geometry before you "fix" your build.
- **Shim-era oracles** (task 070): `WMode` was hiding *motion*, not just
  columns. Under cnc-ddraw, art that looked static animates — any two-sample
  comparison written against WMode is suspect.
- **Issue #97's chain is fixed** (#105) but junction the `.venv` if anything
  complains.
- The launch lock now deletes its file and **fails fast if this process already
  holds it** (#105) — pass `-NoLaunchLock` to nested helpers rather than
  wondering why a call stalls.

## Steps (suggested)

1. Read 070's PR and card. Then find where those four rects are initialised —
   dialog init is the likely place, and 070 named it as the direction.
2. Move ONE element first (the resource bar is the simplest) and prove clicks
   and drawing both followed it before moving anything else.
3. Then the card, then decide about the strip.

## Acceptance criteria

1. **Resource bar at the window's top-right and command card at its
   bottom-right at 800 wide**, shown in a real window capture (path, not
   `pr-image`).
2. **Clicks follow the controls** — demonstrated, not reasoned. A command-card
   click at its new position issues the command it names.
3. **The four must-not-break items above still pass**, `test-production-queue.ps1`
   included, in a run you show me.
4. A stated decision about the dead strip, with what you tried.
5. At 640 (flag off) **everything is exactly as it was** — this is the check that
   matters most, because the user plays that build today.
6. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it in the body.

## Stop-line

**Three honest attempts, then report.** If dialog positions turn out to be baked
into art offsets or hit-test tables that assume 640, that is a real finding and a
follow-up task — 034, 064 and 068 all produced their best work by stopping at
exactly this line. **A measured "the console cannot move without X" is a good
deliverable.**

## Machine

**Task 070 is using it and has priority** — it is finishing the driven session
that produced your briefing. **Message the conductor before your first launch.**

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/071-console-at-800.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
