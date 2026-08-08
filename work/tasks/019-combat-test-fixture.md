# Task 019 — Combat-capable generated maps: enemy force + kept triggers

## Status

agent: 019
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/19
merged: 2026-08-08

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task019 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task019-combat-test-fixture.
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

- Your inbox: `C:/git/decompile-sc/work/messages/019/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 019 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Generated test maps gain combat: an enemy force that can kill our units on demand, so tests can
finally prove death behavior IN-GAME.** This closes the standing gap from tasks 014/017: every
died-while-displayed code path (circles module staleness guards, HUD row liveness + click gate) is
proven offline only, because the 016 fixture is combat-less by design. After this task, a test can
box >12 units, get one killed by an enemy, and assert what the plugin does about it.

## Context

- Build on `tools/make_test_map.py` (tasks 013/016 — read `tools/README-test-map.md` first,
  especially the root causes: SIDE=0x05 melee behavior, mission triggers ending games, FORC
  randomize bit). The generator refuses inputs it cannot edit faithfully — keep that property.
- What is needed, minimum: a second, COMPUTER-owned force (a few attackers, e.g. zerglings or
  marines) placed at a documented distance from the player block, with the computer slot
  configured so its units actually attack when approached (or a documented trigger that orders
  the attack) — and NO trigger that ends the mission when either side loses units. The map must
  still idle indefinitely otherwise (016's no-auto-end property preserved).
- Trigger authoring: 016 STRIPS triggers. You now need to WRITE at least computer-AI/attack
  behavior. Options, cheapest first: (a) no triggers at all — melee AI on the computer slot may
  suffice if it attacks (test on the UMS template; evidence needed); (b) a minimal synthesized
  TRIG section (structures documented in `tools/inspect_map.py`); (c) preplaced enemy units with
  aggressive unit types that attack on sight when the player walks into range (no AI needed).
  Pick with evidence; the repo's evidence rule applies to any new CHK claims.
- Prove it with a NEW test step or standalone test: generate the combat map, box the player
  units, walk them into the enemy, wait for a death (plugin logs per-unit state — `UNITSTATE`,
  `burrowed=`, HP readable via CUnit+0x08 per command-opcodes.md §6), assert the death was
  observed in-process. Then assert the 017 behavior: the dead unit disappears from the HUD row
  (UnitAlive HP term) — the first IN-GAME validation of that path.
- Test discipline as established (015/016/017): pinned ids, positive asserts with preconditions,
  no arrival/timing ambiguity, try/finally, close by -ProcessId, SHA-256 both sides, map deleted
  in finally, no vacuous passes.
- Do NOT touch tools/plugin/src (the plugin needs no changes for this — if you find it does,
  STOP and message the conductor first; parallel worker 018 is active in tools/ and plugin src
  changes would collide with the next queued plugin tasks).
- Generated maps stay uncommitted (gitignore covers *.scm/*.scx); the generator + tests are the
  artifacts.

## Hard rules

1. Never modify, write to, or launch `C:\sc-install\Starcraft`. Working copy only.
2. Offline, single-player only.
3. `StarCraft.exe` on disk stays byte-identical; tests assert it.
4. Commit no game content, no binaries, no logs, no generated maps.
5. Do not merge your own PR.

## Acceptance criteria

1. `make_test_map.py` can generate a combat variant (flag/option), documented in
   README-test-map.md, with evidence for every new CHK claim (how the enemy force is made to
   fight: AI flag, trigger bytes, or unit-type behavior — cited, not guessed).
2. The combat map: loads as UMS, spawns exactly the placed units for both slots, does NOT
   auto-end on unit losses, player units die when engaged — all verified in-process.
3. New unattended test: >12 units boxed, at least one killed in combat, the death observed
   in-process AND the 017 HUD-row consequence asserted (dead unit leaves the row; row state
   consistent). 0 failures, run twice.
4. Existing suites still green (test-selection-circles, test-fanout-orders, test-burrow-fanout,
   test-hud-row); exe byte-identical; no stranded processes; CI green.
5. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/019-combat-test-fixture.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
