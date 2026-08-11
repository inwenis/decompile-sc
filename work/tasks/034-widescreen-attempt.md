# Task 034 — Attempt the wider playfield: stages 0-2 of the renderer plan

## Status

agent: 034
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task034 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task034-widescreen-attempt.
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

- Your inbox: `C:/git/decompile-sc/work/messages/034/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 034 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Actually try it: make the playfield bigger than 640x400 in a running game.** The user came
back on task 032's NO-GO with "remastered managed to produce a wider screen - can we do the
same?" They are right that it is possible — Blizzard did it by replacing the renderer wholesale
and shipping new art, which we cannot copy. But 032 wrote a staged plan (`research/renderer-viewport.md`
§9.3) and nobody has executed it. This task executes stages 0-2 and finds out where it really
breaks, in a running game, rather than on paper.

## Context

- **READ `research/renderer-viewport.md` FIRST, cover to cover.** Task 032 mapped this: the
  single 8-bit framebuffer descriptor at 0x006CEFF0 (640x480, `SMemAlloc(0x4B000)`), the present
  blit 0x0041D420 with its hardcoded source pitch 0x280, the `GraphicLayer[8]` array at
  0x006CEF50 composed 7->0 with **layer 5 as the playfield** (640x400 at (0,0), draw 0x004BD580),
  and §7's numbered breakage list. §9.3 is your plan. Do not re-derive any of it; extend it.
- **THE DECISION THAT REOPENS THIS, and it is mine, so it is not yours to relitigate:** 032
  weighed "stock HUD" against new art and concluded a wider screen leaves "a 160-pixel strip of
  nothing at the bottom, or new art". **We take the strip of nothing.** Hard rule 1 forbids
  shipping game art, so new console artwork is out permanently — but a stock 640-wide console
  sitting under a wider playfield, with the remainder left blank or the console centred, is a
  perfectly acceptable outcome for this user and this project. If the honest result is "it works
  and the bottom strip is empty next to the console", that SHIPS. Do not treat cosmetic
  incompleteness as failure.
- **What is genuinely unknown, and what this task is really for:** §7 items 8-14 plus the terrain
  scratch surface — 032 called stage 2 "the stage that can actually look wrong" and expected it
  to consume most of the budget. That is the question: does the playfield geometry generalise, or
  is 640/400 so deeply open-coded (~30 sites) that stage 2 cannot be completed at this price?
  A truthful "stage 2 defeated me, here is exactly where and why" is a GOOD outcome — it converts
  032's paper estimate into a measured one. What is NOT acceptable is quietly shipping stage 0/1
  as if it were the feature.
- **Stage discipline, because this is the biggest thing anyone has attempted here:**
  - Work the stages in §9.3's order. After EACH stage the game must still run and the existing
    in-game suites must still pass. A stage that breaks them is not done.
  - Everything behind ONE off-by-default flag from the first commit — nothing in this task may
    change the game for anyone who has not asked for it. `StarCraft.exe` on disk stays
    byte-identical; every change is a runtime patch, as with every other feature here.
  - Target ONE larger size first and say which (800x600 is the obvious first step: it keeps the
    HUD strip's relationship simple and is a modest jump from 640x480). Do not build a
    general resolution system.
- **KILL CRITERIA — read these, they are permission to stop.** Come back to me rather than
  grinding, if any of these happen:
  - stage 2 needs more than roughly a dozen distinct patch sites beyond §7's list;
  - the terrain scratch surface (672x448, pitch and wrap size inlined in the blitter) turns out
    to need reallocation you cannot do safely from the plugin;
  - the game runs but the playfield renders visibly wrong and two attempts to fix it have failed;
  - you find yourself needing new art to make it look right.
  Message me with what you found. This task's value is the measurement even if the feature never
  lands.
- **Verification is a READ-BACK, not a screenshot** — game frames reproduce artwork (AGENTS.md
  "Screenshots vs hard rule 1"). Task 032 already built the instrument: `%SCPLUGIN_SCREENSCAN%`
  and `tools/plugin/probe-screen-layout.ps1`, which reads the framebuffer descriptor and all
  eight layer rects out of the running game, and reads TWICE (menu and in-game) so "layer 5 is
  the playfield" is a control rather than an assumption. Extend that probe: your success
  condition is layer 5's rect and the framebuffer descriptor reading the NEW size in a live game,
  with the HUD dialogs still at their stock coordinates.
- **The one thing a read-back cannot tell you is whether it LOOKS right.** If you reach a state
  worth a human's eyes, say so and I will look at it myself — do not commit a frame capture.
- Test discipline: own `Maps\BroodWar\00-t034\`, `Select-ScBrowserMap`, `run-ci-local.ps1`.
  You have the machine to yourself unless I tell you otherwise; task 033 may also want it, so
  take the launch lock and never kill another worker's game. GitHub Actions is billing-blocked.

## Acceptance criteria

1. Stage 0 and stage 1 of §9.3 implemented behind one off-by-default flag, each verified by the
   screen read-back in a running game, with the existing in-game suites still green after each.
2. Stage 2 attempted, and its outcome stated honestly: either the playfield renders at the new
   size (read-back proves layer 5 and the framebuffer descriptor carry it, HUD dialogs unmoved),
   or a precise account of what defeated it — which sites, what you tried, what you would need.
3. `research/renderer-viewport.md` updated with what execution taught that reading could not:
   every §7 item confirmed, corrected or newly found, and 032's paper estimate replaced by a
   measured one.
4. If it renders: I get told so I can look at it, and the empty strip beside the console is
   documented as an accepted limitation rather than a defect.
5. `StarCraft.exe` byte-identical; nothing changes with the flag off; no new art; no stranded
   processes.
6. PR opened, link in Status.pr — even if the answer is "stage 2 is not reachable", because the
   measurement is the deliverable.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/034-widescreen-attempt.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
