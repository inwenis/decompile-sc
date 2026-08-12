# Task 054 — Plugin state has no game-session epoch: seven cross-game survivors, one mechanism

## Status

agent: 054
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task054 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task054-game-session-epoch.
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

- Your inbox: `C:/git/decompile-sc/work/messages/054/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 054 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

No plugin state may survive into a game it does not belong to. Install ONE
game-session epoch and make every cross-frame record carry it, so the seven
known cross-game survivors — starting with the one the user can hit in normal
play (#63) — all stop being possible by construction rather than by seven
separate guards.

## Context

- **Issues: https://github.com/inwenis/decompile-sc/issues/67 (the class) and
  https://github.com/inwenis/decompile-sc/issues/63 (the instance the user
  hits).** Read both in full; #67 carries the complete inventory with file and
  line for all six siblings, and this task file does not repeat it.
- **#63 is measured, not theorised.** Task 051 reproduced it end to end on
  2026-08-12: a fanout process queued 8 Probes over the engine's cap in game A,
  then loaded a save whose own file contains a queue of four and no overflow —
  and the plugin walked into the loaded game still holding three items, bound to
  `unit=0x00623E58`, the address the restored Nexus now occupies. Its arm-6
  assertion (`the plugin holds NOTHING for a game it never queued in`) is the
  regression test and it is already on main in `test-save-load.ps1`.
- **Why every existing guard fails, and it is the same reason each time.**
  `RecordStillLive` and its equivalents ask "is the unit at this address still
  the same unit?" using unit pointer + uniqueness + player + hp + a list walk. A
  save restores all of those VERBATIM into the engine's static 1700-slot table,
  in place, at the same address. So a record from another game reads as
  perfectly alive. **No per-unit check can fix this** — the discriminator has to
  be something the unit does not carry.
- **The fix shape #67 proposes, which you should evaluate before adopting:** one
  `g_session` counter, bumped from the engine's own game-start clear at
  `0x004EEC30` — an address this repo already knows and already hooks
  (`sc_fanout.cpp:989`) — stamped into every record, with `r->session ==
  g_session` added to every liveness check. If that address is not the right
  clock (e.g. it does not fire on a LOAD, only on a new game), say so with
  evidence and propose the one that is. **Take the address from the engine's own
  instructions, not from the global next door** (AGENTS.md, task 038).
- **The subtle one is #67's item 4, `g_shadowVersion`.** It is a counter meaning
  "the selection changed", and `sc_hudrow.cpp:328` trusts it. A counter cannot
  express "different game": unchanged across a load reads as "same selection",
  so the HUD row keeps the previous game's page and list until the first commit.
  A version number and an epoch are different things; do not conflate them.
- **`sc_circles.cpp` item 6 is the one that can outlive even a correct epoch
  check if you are careless** — it holds `CSprite*` HEAP addresses across game
  end, and heap reuse at the same address defeats the sprite comparison. An
  epoch fixes it only if the epoch is checked BEFORE the pointer is
  dereferenced.
- Every `Init` runs once from `DllMain` (`scplugin.cpp:862-890`). There is
  currently no per-game initialisation point at all; creating one is most of
  this task.
- **This is a hobby project** (AGENTS.md, and the user's own words): the goal is
  the happy path working with low complexity. One counter and a stamp is the
  right size. A general-purpose lifetime framework is not.

## Steps (suggested)

1. Confirm the clock first. Find where the engine actually starts a game AND
   where it finishes a load, and prove your chosen hook fires on both — a
   load-that-does-not-bump is the failure mode that makes everything below
   silently useless.
2. Install the epoch and adopt it in `sc_prodqueue` first, because #63 already
   has a passing regression test waiting for it in `test-save-load.ps1`.
3. Then the other five, in #67's order. Each adoption is small; the risk is
   forgetting one, so enumerate from #67's list and tick them off in the PR.
4. Then look for a seventh nobody has found. #67's inventory came from one
   reading; say what you did and did not sweep.

## Acceptance criteria

1. `test-save-load.ps1`'s over-cap crossload arm — arm 6 — goes from FAIL to
   PASS, run and shown. That is the user-visible bug and it already has an
   oracle, so no new test is needed to prove it.
2. Every one of #67's six siblings is either adopted onto the epoch or has a
   stated measured reason it does not need it. A list with all six named.
3. Evidence that the epoch actually bumps on BOTH a new game and a load —
   logged from a real run, not argued from the source.
4. A test that fails without the epoch for at least one sibling OTHER than
   `sc_prodqueue`, so the mechanism is not proven only by the case that already
   had a test.
5. No per-frame cost that shows up in a run's own timing lines; say what you
   measured.
6. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it in the body. Task 053 is in flight fixing the
   receipt gate itself; if its change has landed by the time you finish, rebase
   onto it and use the new behaviour.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/054-game-session-epoch.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
