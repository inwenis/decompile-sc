# Task 062 — A map the user can load to exercise every feature in a minute

## Status

agent: 062
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task062 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task062-feature-test-map.
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

- Your inbox: `C:/git/decompile-sc/work/messages/062/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 062 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

The user can double-click one thing, be in a game within seconds, and exercise
every feature this plugin adds in about a minute — without setting up a base,
without waiting for build times, and without reading anything longer than one
page.

## Context

- **The user asked for this (2026-08-13T08:28Z):** *"can you make me a saved map
  where i can quickly test our features?"* — in the same message where they
  confirmed the fifth-slot fix and the group queue indicator work, and reported
  a bug neither our suites nor our oracles had found.
- **That is the point of this task.** They keep finding things automation does
  not. Two of tonight's user-reported bugs were invisible to green suites. This
  is not a convenience; it is lowering the cost of the most effective bug-finding
  process this project has.
- **Hard rule 1 governs the deliverable shape.** A `.scm`/`.scx` is game content
  and must NEVER be committed — `.gitignore` blocks it and the CI
  `game-content-guard` step will fail the build. So the repo gets a **generator**
  and a **card**; the map itself is written to disk outside the repo.
- **The generators already exist and are proven.** `tools/make-test-map.py` and
  the fixture builders every suite uses — including UNIx build-time overrides
  (task 051 set Probe build time to 240s), pre-placed units, starting resources
  via triggers, and `SIDE`/`OWNR`/`FORC` control. Read `test-save-load.ps1`'s
  fixture call and `make-test-map` first; nearly everything needed exists.
- **Features to exercise, and what each needs** (confirm against the suites
  rather than trusting this list):
  1. **over-cap production queue** — a building plus enough minerals to queue
     8+; long build times so the queue does not drain while they look at it.
  2. **the `+N` overflow indicator and the fifth slot** — same setup.
  3. **cancel-by-click, including the last slot** — this is issue #061's bug;
     the map should make it trivial to retry once fixed.
  4. **the group queue line** — several buildings of one type, selectable as a
     group.
  5. **the >12-unit paging row** — 13+ units in one selection, and note issue
     #44: a BUILDING group past twelve has never been exercised.
  6. **save/load** — nothing special needed beyond a state worth reloading.
  7. **selection circles / building groups** — whatever the existing suites use.
- **Long build times are the single most important property.** Every one of
  these features is a thing the user must LOOK at. A 20-second Probe drains the
  queue before they can read it. Task 051 already learned this and used 240s.
- **The card matters as much as the map.** One page: what to click, in what
  order, and what should happen. Written for someone who has not read the source
  — because that is who will use it at 9am on a Saturday.
- **Where the map lands is a user-state decision.** Their play copy is
  `C:\sc-deploy\starcraft-modded\game\`. Writing a map into its `Maps\` tree is
  reasonable, but `deploy.ps1` mirrors that directory with `/MIR` and would
  DELETE anything not in the source tree on the next deploy. Work out where it
  survives a redeploy, say so explicitly, and do NOT write anywhere under
  `save\`, `characters\` or `Maps\Replays\`.
- **This is a hobby project.** One map that covers most features beats five
  perfect ones. If a feature needs a fundamentally different setup, say so and
  leave it out rather than contorting the map.

## Steps (suggested)

1. Read `make-test-map.py` and two suites' fixture calls before designing
   anything.
2. Draft the feature-to-fixture table and send it to the conductor for the user
   to confirm BEFORE building — they may not want all seven, and they know what
   they actually test.
3. Then build the generator, generate the map, and write the card.
4. Then load it yourself, once, and walk the card top to bottom.

## Acceptance criteria

1. A generator committed to the repo that produces the map deterministically.
   **The map file itself is NOT committed** (hard rule 1).
2. The map generated and placed where the user can load it, at a path that
   survives `deploy.ps1` — with the survival explained, not assumed.
3. A one-page card: click this, expect that. Plain language, no source
   references, ordered so the fastest checks come first.
4. **You walked the card yourself in a real game** and every step behaves as
   written. If a step cannot be made to work, it is not on the card.
5. A stated list of what the map does NOT cover and why.
6. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it in the body.

## Machine

**THE USER IS PLAYING RIGHT NOW.** StarCraft is single-instance per machine.
**Do NOT launch anything until the conductor says the machine is free.** Design
and generate offline; the map can be built without running the game. Message the
conductor when you need a run.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/062-feature-test-map.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
