# Task 030 — Queue units at every selected production building

## Status

agent: 030
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/32
merged: 2026-08-10

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task030 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task030-group-production-fanout.
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

- Your inbox: `C:/git/decompile-sc/work/messages/030/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 030 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**With several production buildings selected, one Train click queues a unit at EVERY one of
them.** User: "can i also queu units when i have several building selected?" Task 024 made a
drag box select all your Barracks; task 025 made one building hold more than five. Nobody joined
them up: a production click almost certainly still lands on a single building.

## Context

- **MEASURE FIRST — you may already have the answer handed to you.** Task 028 is in a live
  production fixture right now and I asked it to report exactly this: with several production
  buildings selected, how many commands reach the engine`s command funnel
  (`queueCommand` 0x00485BD0), which building tags they carry, and which buildings actually gain
  a queued item read from each building`s own memory (`CUnit+0x98`). Check
  `work/messages/conductor/read/` for its answer before spending a launch on your own. If it has
  not reported yet, ask me rather than duplicating the run — you two share one machine.
  If it turns out this ALREADY works, say so and stop; the task is then a test, not a feature.
- **The likely finding, not to be assumed:** one command, one building. The >5 queue work was
  scoped to one building`s own queue on purpose, and the card is drawn for the primary selection.
- **This is a FAN-OUT, and the fan-out already exists.** `tools/plugin/src/sc_fanout.cpp` replays
  a command across the whole shadow selection by emitting Select+order pairs in chunks of
  `simSlots` — that is how move/attack/patrol/abilities already reach more than 12 units, and how
  task 024 rallies a group of buildings. `research/binary-selection-map.md` and
  `research/building-groups.md` are the prior art. The question this task answers is whether a
  TRAIN command (0x1F, `research/command-opcodes.md`) can ride that same path, or whether
  production is special.
- **Three things make production different from a move order. Reason about each explicitly:**
  1. **It costs money.** N buildings means N units paid for. The player clicked once — do they
     expect N units and N x cost? I think yes (that is the point), but the failure modes are
     paying for units that never queue, or queueing at a building that cannot afford it. Every
     item must enter through the engine`s own accept path so the ENGINE checks affordability and
     deducts, exactly as task 025 concluded (`sc_prodqueue.cpp`, and its `mineralsSpent = 0`
     assertion for the plugin). The plugin must not spend.
  2. **Buildings differ in what they can build.** A group may hold a Barracks and a Factory, or
     buildings at different tech. Task 024 already restricts a box to ONE type, which mostly
     sidesteps this — but a mixed selection made by shift-click may not be one type. Decide and
     state what happens: refuse, or queue only where the unit is valid.
  3. **A building`s queue can be full.** With task 025 the cap is 16, but a building at the cap
     must be skipped cleanly rather than silently eating a click or a payment.
- **Interaction with 025 and 028, both live:** 025`s plugin holds overflow items itself and 028
  is proving its cancel/refund path in-game. Prefer NEW code over editing `sc_prodqueue.cpp`;
  if you must touch it, rebase and tell me rather than guessing a merge. Append to
  `sc_addresses.h` at the end. You share the machine and launch lock with 028 and 029 — wait,
  never kill another worker`s game.
- **Watch the wire before believing any handler** (AGENTS.md, from task 025): a player-input
  feature is unproven until the engine`s command funnel has been watched in a real game. That
  rule exists because 025`s first design handled a command the client never sends.
- Test discipline: own `Maps\BroodWar\00-t030\`, `Select-ScBrowserMap`, `New-ScFixtureRun`,
  `run-ci-local.ps1` (`ruff` NOT RUN is fine, it is optional). GitHub Actions is billing-blocked
  repo-wide; ignore it. The harness no longer raises the game window — run
  `watch-foreground.ps1` alongside and report what it saw.

## Acceptance criteria

1. The CURRENT behaviour established from evidence first (yours or task 028`s, cited either way):
   how many commands reach the funnel and which buildings gain an item, with a plain statement of
   whether this already works.
2. If it does not: the feature built so one Train click with N production buildings selected
   queues one unit at each, with the design stated — and every item entering through the engine`s
   own accept path so the plugin never spends.
3. In-game, unattended: N buildings selected, one click, then read EACH building`s queue from its
   own memory and assert each gained exactly one. Not from the UI.
4. Resources reconcile: exactly N x cost deducted, asserted from the resource globals. Nothing
   paid for that did not queue.
5. The awkward cases stated and handled, with evidence: a building already at its queue cap, and
   a selection whose buildings cannot all build the unit. Refusing is an acceptable answer; a
   silent payment is not.
6. Behind its own flag if it moves resources, like `-ProdQueue`. Tell me the flag name for the
   deployed launcher.
7. No regressions: existing in-game suites + hooktest green; `StarCraft.exe` byte-identical; no
   stranded processes; fixture removed.
8. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/030-group-production-fanout.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
