# Task 014 — Draw selection circles on the fan-out units

## Status

agent: 014
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task014 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task014-selection-circles.
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

- Your inbox: `C:/git/decompile-sc/work/messages/014/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 014 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Draw selection circles under the units that fan-out commands but the engine does not consider
selected.** Right now the user box-selects 24 units, all 24 obey a right-click, but only 12 have
circles — so the game looks like it is ignoring half the group even though it is not. Their words:
"more units moved but they were not selected with circles in the map - can we fix that next".

Scope is **the green circles on the battlefield only.** The portrait/wireframe row at the bottom
of the HUD is explicitly OUT of scope and is a later task — it is a fixed 12-slot dialog and
involves layout work, not just data.

## Try the cheap route first

Do not start by relocating arrays. `research/selection-cap.md` §2.4 records, from two independent
sources, that each unit's sprite carries its own selection state:

- `CSprite` has a `selectionIndex` byte at offset `0x0B`, documented as "0 <= selectionIndex <= 11,
  index in the selection area at bottom of screen".
- Sprite flags include **`0x01` = draw selection circle** and **`0x08` = selected**.

If the circle is drawn from a per-sprite flag, then the fix may be as small as setting that flag on
the shadow-selected units each frame and clearing it when the selection changes — no array
relocation, no cap change, nothing touching the simulation. That would be dramatically cheaper than
candidate #3 in the research.

**Verify that before building on it.** Those offsets are inherited from prior art and confirmed
only as far as our own sweep went. Prove the flag actually drives rendering before you rely on it.

**Known hazard, stated in the research:** `selectionIndex` is not decorative. GPTP computes a
memmove length from it when shift-clicking a unit out of the selection. Writing a bogus index, or
setting a flag while leaving the index stale, risks corrupting the real selection. Work out what a
safe value is for a unit that is fan-out-selected but not engine-selected, and say what you chose
and why. If there is no safe value, that is a finding — report it rather than guessing.

If the sprite-flag route turns out not to work, fall back to candidate #3 (widen the client-side
selection state) but **report before switching** — that is a much bigger change and I want to
decide, not discover it in a diff.

## You can test this yourself now — this changed today

Task 012 proved a script can drive this game. Posting `WM_LBUTTONDOWN` / `WM_MOUSEMOVE` /
`WM_LBUTTONUP` to the game's `SWarClass` HWND with client coordinates in `lParam` works,
demonstrated live: a posted click moved the game's own rendered cursor to the exact point. Focus is
not required; the window must not be minimised. **No screen coordinates are involved**, which is
why the old `SendInput` failure class does not apply. See `research/automated-testing-options.md`
§4.1 — that PR is not merged yet, so read it at `C:/git/decompile-sc-task012/`.

So: drive the menus, load a map, post a drag-box, issue an order, and read back your own state —
all without a human. **Do not burn user round trips on iteration.** The one thing you cannot do is
see the screen, so the *final* confirmation that circles are visibly drawn still needs the user.
Get everything else right first, then ask once.

`SendInput`/`SendKeys` remain banned (`config/guard-destructive.ps1`). Posted messages are fine.

## Context

- The fan-out plugin is merged and on `main`: `tools/plugin/src/sc_fanout.cpp` holds the shadow
  selection list, which is exactly the set of units that need circles.
- Verified live and usable verbatim: module base `0x00400000`, relocation delta zero. `CUnit` is
  336 bytes. Active player was 1, not 0 — read it, do not hardcode.
- The count byte and the selection array can disagree during transitions; validate pointers rather
  than trusting a count.
- Map for testing: `Maps\campaign\(1)Enslavers02b.scm` (stock, 24 units in one drag box, human is
  Player 2). Menu path: Single Player → Expansion → Play Custom → browse into `Maps\campaign\`.
- `tools/plugin/run-with-plugin.ps1` launches with the guard and windowed helper;
  `tools/plugin/close-game.ps1` shuts it down cleanly.

## Hard rules

1. **Never modify, write to, or launch `C:\sc-install\Starcraft`.** Working copy only.
2. Offline, single-player only. Never Battle.net.
3. Patch memory in-process only — `StarCraft.exe` on disk must stay byte-identical to pristine.
   Hash it and show the result.
4. Keep the off switch working: a mode where the plugin is passive must still give a stock game.
5. Commit no game content, no binaries, no logs, no screenshots (they reproduce game artwork).
6. Do not merge your own PR.

## Acceptance criteria

1. Circles are drawn under the fan-out units, or a clear report of why the cheap route does not
   work and what the real cost is.
2. Whatever you did about `selectionIndex` is stated explicitly, with the reasoning.
3. Shift-clicking a unit out of the selection still behaves correctly — this is the specific thing
   the `selectionIndex` hazard threatens. Test it, do not assume.
4. Fan-out still works: more than 12 units still obey one order. Do not fix the visuals and break
   the feature.
5. Self-tested via posted window messages as far as possible; the user asked for once, at the end,
   only for "do the circles actually appear on screen".
6. On-disk executable unchanged, passive mode still stock, no game process left running, CI green.
7. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/014-selection-circles.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
