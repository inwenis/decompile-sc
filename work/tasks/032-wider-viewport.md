# Task 032 — Wider viewport, stock HUD: map the renderer and price it

## Status

agent: 032
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/33
merged: 2026-08-10

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task032 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task032-wider-viewport.
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

- Your inbox: `C:/git/decompile-sc/work/messages/032/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 032 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**See more of the map at once — a bigger playfield, like Remastered, while the HUD stays stock.**
The user asked to "investigate making the screen bigger like in remastered" and, given three
options, chose the hybrid: **a wider/taller VIEWPORT with the vanilla HUD**, explicitly rejecting
a mere upscale of the same 640x480 image. This task is INVESTIGATION AND PRICING FIRST. Do not
start rewriting the renderer.

## Context

- **The honest starting position: nobody here has mapped the renderer at all.** Every subsystem
  this project has touched so far (selection, orders, production, the command card, the status
  pane) is game logic and dialogs. The screen is different territory, it is the largest unknown
  on the roadmap, and I told the user I would not put a cost on it before it was mapped. So the
  primary deliverable is a MAP AND A PRICE, not a feature.
- **Answer, in order, with evidence:**
  1. Where does 640x480 actually live? Constants, the surface/back-buffer allocation, the blit,
     the palette/DirectDraw path. `WMode.dll` is already injected for windowed mode (see
     `run-with-plugin.ps1 -InjectWindowedHelper WMode`) — establish what it does and does not
     change, because a helper that already reshapes presentation is either a lever or a
     constraint.
  2. What is genuinely viewport-sized versus screen-sized? The playfield is drawn into a region;
     the HUD (console, minimap, command card, status pane) is drawn over it at fixed coordinates.
     Find the seam. `research/hud-selection-row.md` and `research/command-card.md` already
     locate HUD dialogs and their coordinates — that is prior art for the HUD half.
  3. What breaks if the playfield is bigger? Name them concretely rather than hand-waving:
     the tile/sprite draw loops and their bounds; scroll clamping at map edges; the minimap
     viewport rectangle; mouse-to-world coordinate mapping (task 024 already reads a viewport
     origin — `research/building-groups.md`); fog-of-war extents; and whether the engine
     allocates buffers sized from the same constants.
  4. Is this reachable with the plugin's tools — patching constants and detouring a few
     functions — or does it need something categorically bigger? Say which, plainly.
- **Deliver a GO/NO-GO with a price.** A short written verdict: what it would take, in what
  order, what is risky, and what a first slice looks like (e.g. "widen to 800x600 playfield,
  HUD unchanged, no minimap change" as a stepping stone). If the honest answer is "this is a
  renderer rewrite and not worth it on 1.16.1", that is a legitimate and useful outcome — say so
  with the evidence, and the user gets to decide rather than being told a fantasy.
- **If, and only if, the map says a small slice is genuinely cheap, take that slice.** A running
  game with a visibly wider playfield and an intact HUD is worth far more than more prose.
  Screenshot it (project rule: UI-visible change → screenshot → `pr-image` → embed in the PR).
  Do not chase the full feature in this task.
- **Hard constraints:** `StarCraft.exe` on disk stays byte-identical — everything is a
  runtime patch from the plugin, as with every other feature here. Offline/single-player only.
  Anything user-visible ships behind its own flag, off by default.
- **Concurrency:** tasks 028/029/030/031 are live and share the machine and launch lock. Your
  work is mostly static analysis, which is a gift — prefer Ghidra over game time, and when you do
  need the game, wait rather than kill. You will likely touch NO file they touch; keep it that
  way if you can, and append to `sc_addresses.h` at the end.
- Test discipline if you do run: own `Maps\BroodWar\00-t032\`, `Select-ScBrowserMap`,
  `run-ci-local.ps1`. GitHub Actions is billing-blocked; ignore it.

## Acceptance criteria

1. `research/renderer-viewport.md` written: where the resolution constants live, the
   playfield-versus-HUD seam, and the draw path from tiles to presented frame. Every address
   carries how-found + how-verified (hard rule 4).
2. The breakage list from context item 3, each entry naming the function or global that would
   have to change and how confident you are.
3. A GO/NO-GO verdict with a staged plan and a first slice, or an evidenced statement that this
   is not worth doing on 1.16.1. Include what you did NOT manage to determine.
4. If a cheap slice existed and you took it: it runs, the HUD is intact, a screenshot is in the
   PR via `pr-image`, and it is behind an off-by-default flag.
5. No regressions: existing suites + hooktest green; `StarCraft.exe` byte-identical; no stranded
   processes.
6. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/032-wider-viewport.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
