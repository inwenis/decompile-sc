# Task 033 — Show that a building has more queued than the strip draws

## Status

agent: 033
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task033 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task033-queue-overflow-indicator.
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

- Your inbox: `C:/git/decompile-sc/work/messages/033/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 033 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**When a building holds more queued items than the status strip can draw, the player must be
able to SEE that.** User, 2026-08-11: "when more then 5 units a queued - is the info showing
that? (some +x number somewhere in tug?)". Today the answer is no: the production strip draws
exactly five icons whatever the real queue length is, so a nine-item queue looks identical to a
five-item one. The same blindness applies to task 030's group training — one Train click on four
buildings shows one queue while four buildings' worth of minerals leave.

## Context

- **This is the display half of two features that already shipped.** `-ProdQueue` (task 025)
  holds items past the engine's five; `-ProdFan` (task 030) queues at every selected building.
  Both are ON in the deployed play build. Neither shows the player what it did. The user has now
  asked about it directly, so it is worth building rather than documenting.
- **What is already known, do not re-derive it:**
  - The strip is the status-pane dialog `statdata` (0x0068C1F0), control ids 2..6 — five queue
    icons, task 028 mapped them and clicks one to cancel. An empty slot's icon is greyed.
  - The plugin already knows the true logical length: `sc_prodqueue.cpp` holds the overflow and
    `test-production-queue.ps1` reads `engineLen + overflow` per building.
  - `sc_hudrow.cpp` (task 017) is the prior art for CHANGING what the status pane shows — it
    pages the wireframe row. That is the closest thing to drawing into this area that exists.
  - `research/hud-selection-row.md` and `research/command-card.md` carry the dialog layout and
    how controls are read and written.
- **The cheapest thing that could work, and I want the cheapest:** a small "+N" drawn near the
  strip when the logical queue exceeds what is drawn. Do NOT build a full nine-slot queue
  display — that is a second dialog splice and much bigger.
  - Find how the engine draws text into the status pane (the resource counters, unit names and
    the "Zerg Egg" style labels are all text in that region — one of them is the model to copy).
    Prefer the engine's own text routine over hand-plotting pixels.
  - If drawing text there turns out to be expensive, say so and propose the next cheapest thing
    you found — e.g. re-using an existing control, or a different position. Come back to me with
    the option rather than building something elaborate.
- **The group-training case is the second half and may be harder:** with N buildings selected the
  strip shows the primary building only. At minimum the user should be able to tell that a click
  went to more than one building. If that turns out to need the multi-select display work 030
  explicitly avoided, then say so with evidence and ship the single-building "+N" alone — that is
  an acceptable outcome, stated.
- **Hard rules:** no new game art committed, ever (hard rule 1) — draw with what the engine has.
  `StarCraft.exe` on disk byte-identical. Off behind its own flag if it draws anything, and tell
  me the flag name for the deployed launcher.
- Test discipline: own `Maps\BroodWar\00-t033\`, `Select-ScBrowserMap`, `New-ScFixtureRun`,
  `run-ci-local.ps1`. You now have `tools/plugin/time-suite.ps1` and `--unit-build-time`
  (task 031) — use the fast fixture, a production suite no longer has to wait 20s per unit.
  GitHub Actions is billing-blocked; ignore it.
- **Verification without screenshots:** game frames reproduce artwork, so the oracle is a
  READ-BACK, not a picture (AGENTS.md "Screenshots vs hard rule 1", and task 032's
  `probe-screen-layout.ps1` / `%SCPLUGIN_SCREENSCAN%` shows the pattern). Assert what the engine
  holds — the control's text/state — rather than what a frame looks like.

## Acceptance criteria

1. How the status pane draws text established with evidence: the routine, where it is called
   from, and how a string reaches a control. Addresses carry how-found + how-verified.
2. With more items queued than the strip draws, the player can see the true count — implemented
   as cheaply as the code allows, and NOT as a full queue-display rewrite.
3. In-game, unattended: queue over the engine's five, then assert from MEMORY that the indicator
   reflects the true logical length, and that it disappears when the queue drops back under.
4. The group-training case either covered, or refused with evidence and a stated reason.
5. Nothing drawn when the feature is off; no new art; `StarCraft.exe` byte-identical.
6. No regressions: in-game suites + hooktest green; no stranded processes; fixture removed.
7. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/033-queue-overflow-indicator.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
