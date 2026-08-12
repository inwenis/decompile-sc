# Task 051 — Does saving and loading a game work with the plugin active

## Status

agent: 051
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/64
merged: 2026-08-12

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task051 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task051-save-load-with-mods.
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

- Your inbox: `C:/git/decompile-sc/work/messages/051/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 051 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Answer the user's question with evidence: **does saving a game and loading it
back work while our plugin is active?** Not "does the save dialog appear" —
does a game saved with the plugin in `fanout` mode load back into a correct,
playable state, and does a save written by the plugin-free game still load
under the plugin. If it is broken, say exactly how and where; if it works, say
what you actually checked so the answer means something.

## Context

- **The user asked this directly (2026-08-12T20:27Z):** *"btw - does saving and
  reading games work? with our mods?"* They play the deployed build daily, so
  this is about their real play, not a lab curiosity.
- **Nobody has ever tested it in fanout mode.** Two save-test logs exist at
  `C:\sc-deploy\starcraft-modded\logs\sc-plugin-savetest3.log` and
  `…savetest5.log` (2026-08-08), and BOTH ran `mode = observe` — read-only, the
  plugin wrote nothing to game memory. The user's deploy runs `mode=fanout`,
  which patches game memory in-process. So the existing evidence covers the one
  configuration that could not have broken anything. Treat the question as
  fully open.
- **Why it is a genuine risk and not a formality.** In fanout mode the plugin
  hooks `queueCommand` (0x00485BD0), `CMDACT_Select`, `sortOverflowHandler`,
  `SortAllUnits`, `CreateNewUnitSelectionsFromList` and `statDataUpdate`, and it
  rewrites production-queue state (task 025's over-cap queueing keeps the
  engine's ring below its cap; task 039 just changed queue-indicator drawing).
  A save file records unit and queue state. The plausible failure modes are
  concrete: a queue the plugin was holding above the engine's own cap is
  serialised, or is silently dropped on save; a load restores a queue the
  plugin's shadow state no longer matches; a hook fires during
  serialisation/deserialisation and sees a half-built world.
- **The engine's own save path**, from AGENTS.md § "Take the ADDRESS from the
  engine's own instructions": `StarCraft.exe`'s strings carry
  `** Single Player Save Format ver %d.%d` next to a bare `save\` fragment, and
  the original source names `saveload.cpp`, `sai_LoadSave.cpp`, `CUnitSave.cpp`.
  Start from the engine's instructions, never from a global next door.
- **HARD RULE — the user's own saves are untouchable.** `C:\sc-deploy\starcraft-modded\game\save\`
  and `…\characters\` hold their real single-player games; `deploy.ps1` excludes
  both from every mirror precisely so they survive. Do all of your work in
  `C:\sc-work\1161-base\` or your worktree. Never read-modify-write, delete or
  overwrite anything under the deploy dir's `save\`, `characters\` or
  `Maps\Replays\`. Copying one OUT to inspect it is fine. If you genuinely
  cannot answer without touching a real save, stop and ask — see the 2026-08-08
  registry-wipe incident in hard rule 5.
- **The wire rule applies (AGENTS.md § "A player-input feature is unproven until
  the wire has been watched").** Saving is a player input: a menu, a filename, a
  button. An offline argument about the save format proves nothing about what
  the client actually writes. Drive the real dialogs.
- Suites and helpers you will want:
  `tools/plugin/run-offscreen.ps1` (default; nothing reaches the user's screen),
  `tools/plugin/run-with-plugin.ps1`, `tools/plugin/drive-game.ps1`,
  and the existing suites as models for fixture setup.
- **Do not click a map-browser row by number** (hard rule, task 023), and if you
  need a dropdown pick, know that it cannot work off-screen — task **050** is
  in flight converting exactly those call sites, so coordinate with the
  conductor rather than reaching for `-Visible`.

## Steps (suggested)

1. Decide what "works" means and write it down BEFORE running anything —
   which fields of the world you will compare across a save/load round trip.
   Queue contents are the interesting ones; assert the ENGINE'S arrays, not the
   plugin's bookkeeping (AGENTS.md § "Assert the ENGINE'S OWN RESULT").
2. Cheapest decisive experiment first: plain game, no plugin — save, load,
   compare. That is your positive control. An "absence" result is worthless
   without it (§ "Absence assertions must first be proved positive").
3. Then fanout mode, ordinary queue (≤ 5 deep). Then fanout mode with a queue
   the plugin is holding OVER the engine's cap, which is the case most likely
   to break.
4. Cross the arms: save under fanout → load without the plugin, and save
   without → load under fanout. The user will do both by accident eventually.
5. If something breaks, find out WHERE (save side or load side) before
   proposing anything.

## Acceptance criteria

1. A plain-English answer to the user's question at the top of the report:
   works / works with caveats / broken, in one sentence.
2. A table of the arms actually run — plugin mode on save, plugin mode on load,
   queue depth, verdict — including the no-plugin positive control. Any arm you
   did not run is listed as not run, never implied to have passed
   (§ "A SKIPPED GATE IS NOT A PASSED GATE").
3. Every verdict backed by the engine's own state after the load, not by the
   plugin's log saying it did the right thing.
4. Evidence that the user's real saves under `C:\sc-deploy\starcraft-modded\game\save\`
   and `…\characters\` are byte-identical before and after all your work
   (hash them at the start, hash them at the end, put both in the report).
5. If it is broken: the failure named precisely enough to cut a fix task from,
   and a GitHub issue opened. Do NOT fix it in this task — this one answers the
   question.
6. `scripts/run-ci-local.ps1` PASS if you change any tracked file. GitHub
   Actions is down on a billing error; the local receipt is the gate and the PR
   body must say so. If nothing tracked changes, report at
   `work/reports/051-save-load-with-mods.md` and there is no PR.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/051-save-load-with-mods.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
