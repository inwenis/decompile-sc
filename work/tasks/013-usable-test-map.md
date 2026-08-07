# Task 013 — Find a stock map with more than 12 units; fix the generator

## Status

agent: 013
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task013 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task013-usable-test-map.
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

- Your inbox: `C:/git/decompile-sc/work/messages/013/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 013 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Get us a **map that StarCraft 1.16.1 actually loads** and that starts one player with **more than
12 units**, so the fan-out feature can be tested. Two parts, in this priority order:

1. **Unblock now: find a STOCK Blizzard map** already in the install that fits. Guaranteed
   loadable, zero corruption risk, available immediately.
2. **Then diagnose ours.** `tools/make-test-map.ps1` produces a file the game rejects as corrupt.
   Find out why and fix it.

Part 1 is the critical path. Do it first and report it before starting part 2.

## What went wrong, so you do not repeat it

Task 009 generated `test-many-units.scx`, validated it by **parsing it back with the same library
that wrote it**, and confirmed 36 Marines, correct owner, valid start location. All true. The game
still rejects it as corrupt.

Round-tripping a file through the library that produced it proves the library is self-consistent.
It proves nothing about whether the game accepts it. That gap reached the user mid-test.

**So: "the game loads it" is the only acceptance test that counts here.** Structural validation is
a useful diagnostic and is worthless as proof.

## Part 1 — find a stock map (do this first)

The install ships roughly 200 maps under `C:\sc-work\1161-base\Maps\` — melee, plus campaign and
scenario maps, many with large pre-placed armies.

- Scan them offline with the map library already pinned in `requirements.txt` (`richchk`), reading
  only. **No game launch needed for this**, which is why it is the fast path.
- Find maps where a single player starts with **more than 12 units** — ideally 20+, ideally simple
  combat units on open ground.
- Prefer: single-player playable, no immediate hostile pressure, units clustered enough that one
  drag-box catches them, and a short path to being in-game (fewer menu steps is better, since a
  human has to drive).
- Rank the top candidates in a short table: map name, unit count and type per player, whether
  hostiles are present, and any caveat.
- Note the reading is our library's interpretation, not proof the game agrees — but for a
  Blizzard-shipped map, loadability is not in question. That is the whole point of preferring one.

## Part 2 — diagnose and fix our generator

Now that you have a known-good stock map, **diff ours against it structurally**. That is the
strongest offline signal available:

- Which CHK sections does the stock map contain that ours does not, and vice versa?
- Do the version/type/tileset/dimension fields match what a 1.16.1 `.scx` carries?
- Is the MPQ container itself well-formed — file table, listfile, the internal `scenario.chk`
  present under the expected name?

Fix `tools/make_test_map.py` / `tools/make-test-map.ps1` accordingly. If `richchk` simply cannot
emit a container this game accepts, **say so plainly** — that is a legitimate finding, and
"use a stock map" becomes the standing answer rather than a workaround.

## Hard rules

1. **Never modify, write to, or launch `C:\sc-install\Starcraft`.** Read stock maps from the
   working copy at `C:\sc-work\1161-base\Maps\`.
2. **Do NOT launch the game without asking the conductor first.** The user is at the keyboard,
   task 011 is mid-test, and task 012 is also running. Message and wait. All scanning and diffing
   is offline and needs no permission.
3. Offline, single-player only. Never Battle.net.
4. **Commit no maps** — no `.scm`, `.scx`, `.chk`, or extracted game content. CI blocks tracked
   game content and will fail the build. You commit code, docs and findings; the stock map is
   already on disk and is Blizzard's, not ours to redistribute.
5. Do not merge your own PR.

## How the final proof happens

A human must load the map — workers cannot reliably drive the menus (documented in
`research/runtime-selection-observations.md` §5: a synthetic click aimed at 1818,935 landed at
1228,1544). When you have a candidate, message the conductor with:

1. the exact map name and where it sits in the Maps folder,
2. the precise menu path to load it,
3. what the user should see (how many units, what race, any hostiles),

and the conductor relays it. **Assume you get one attempt.** Recommend a single map, not a
shortlist for the user to work through.

## Acceptance criteria

1. A named stock map identified, with its unit count and owner as read from the file, plus the
   exact menu path to load it. Reported to the conductor as soon as it is found — do not sit on
   it until part 2 is done.
2. A short ranked table of alternates, so a second attempt costs no further investigation.
3. Part 2: either our generator is fixed with a concrete explanation of what was wrong, or a
   plain statement that the library cannot produce a loadable container, with the evidence that
   led you there.
4. Any claim that a map "works" is backed by an actual in-game load — by the user, relayed
   through the conductor. Structural validation alone must be labelled as unproven.
5. No game content committed. CI green. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/013-usable-test-map.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
