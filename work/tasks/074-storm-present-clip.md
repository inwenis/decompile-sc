# Task 074 — Make the window show all 800 columns in game

## Status

agent: 074
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task074 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task074-storm-present-clip.
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

- Your inbox: `C:/git/decompile-sc/work/messages/074/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 074 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**The engine computes 800 columns of correct, fogged map. The window shows the
user 640 of them.** Every widescreen task so far measured the framebuffer, which
was genuinely right; the step that copies that buffer to the screen has been
clipping to the old boundary the whole time, and nobody looked until task 073.

Make the in-game window present all 800 columns.

## Context

- **This is the last thing between the user and their stated goal**
  (2026-08-13T09:18Z): *"i want to be able to play and see more of the map."*
  Everything else is merged and measured: playfield geometry (#99), fog (#104),
  input geometry (#110), a non-cropping presenter (#98), one-switch deploy
  (#108). **The picture is computed and never delivered.**
- **READ `research/renderer-viewport.md` §19, especially §19.8** — task 073's
  account, written as your briefing. Then `work/reports/073-*` and PR #111.

### What 073 established, and is not yours to re-derive

1. **The storm present clips against a base region `0x6D5E14`**, which
   `0x0041D470` rebuilds from the screen-image list. `imgCreate` (`0x0041D640`)
   has **exactly one caller in the binary** — the `console.pcx` loader, node
   `(0,0,640,480)`. Nothing ever told the present path the screen got wider.
2. **Adding an extra image node `(640,0)-(800,480)` through the engine's own
   `imgCreate` was tried.** It makes the region right and the composite land at
   the new rect — and the glass still stops. **Five runs exhausted every
   exe-side constant.** All are named in §19.8; do not re-walk that list.
3. **The remaining 640 is storm-internal** — inside `storm.dll`'s buffer→glass
   present, not in `StarCraft.exe`. **That is where this task starts.**
4. **Dialogs escape the clip entirely** because they blit direct to the locked
   surface. That is why menus, and 073's moved command card, appear correctly at
   x>640 while the playfield does not. **A fix that only makes dialogs work is
   not a fix.**

### The instrument that makes this task possible

**`probe-console-edge.ps1` carries a buffer-vs-glass two-number reading** —
`Get-BufferDump` band beside a caption-corrected window band, reported side by
side. **Use it as your primary oracle and do not build another.**

**It exists because every glass capture this project ever took was misread,
including by the conductor**, who looked at a black right band in task 070's
in-game window and reported "the map genuinely reads as wider" to the user. The
buffer said 800, the glass said 640, and nobody compared the two numbers until
073. **Two numbers, every run, or you will repeat it.**

### Constraints

- **`storm.dll` is a Blizzard binary and is patched at RUNTIME, exactly like
  `StarCraft.exe`** — on-disk bytes stay identical, and that is checked. Follow
  the existing pattern in `tools/plugin/src/` for module-relative addressing;
  `storm.dll`'s base is not fixed, so **every address must be resolved from the
  loaded module**, not hardcoded like the exe's.
- `research/pe-anatomy.md` covers `storm.dll`'s layout and notes it imports
  nothing from `ddraw` — relevant, because cnc-ddraw sits *below* this clip and
  cannot fix it.
- Off by default; off-screen only (task 043); never the user's screen, install,
  display settings or registry.
- **Game frames NEVER go through `pr-image`** — hard rule 1. Paths travel.

### What must not break

1. Cancel-by-click at every hold duration (#102: 84/84 at 40-200ms) —
   `test-production-queue.ps1`.
2. `test-widescreen-input-800.ps1` both arms.
3. **At 640 / flag off: byte-for-byte stock.**
4. The menus, which currently render correctly and have their own path.

### The user-facing state you are fixing

`tools/widescreen-card.md` now tells the user, in their language, that the right
quarter is black in game and that this is being worked on. **If you fix it, that
card correction gets reverted to the truth — and if you cannot, it stays.**
Either way the card must match reality when your PR merges.

## Steps (suggested)

1. Read §19.8. Then reproduce 073's two-number reading on an unmodified stage-3
   build so you own the baseline.
2. Find the clip inside `storm.dll` — the present that copies the locked surface
   to the window.
3. One change, one capture, two numbers.

## Acceptance criteria

1. **A cnc-ddraw in-game window capture showing map past x=648** (path, not
   `pr-image`), with 073's buffer-vs-glass numbers agreeing for the first time.
2. `storm.dll` and `StarCraft.exe` byte-identical on disk; all addresses resolved
   from the loaded module.
3. The must-not-break list passes in a run you show me.
4. The card updated to whatever is then true.
5. If it is structural: the mechanism at §19.8's standard, and the card stays as
   it is. **A measured "the window cannot show it because X" is a complete
   deliverable** — 071's and 073's NO-GOs are what made each next step possible.
6. `scripts/run-ci-local.ps1` PASS **on a clean tree** — a dirty-tree receipt is
   refused by the gate and has cost two tasks a round trip today.

## Stop-line

**Three honest attempts, then report.** You are the fourth task on this feature;
each of the previous three stopped at its line and each produced the finding the
next one needed.

## Machine

The board is otherwise empty. **Message the conductor before your first launch.**

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/074-storm-present-clip.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
