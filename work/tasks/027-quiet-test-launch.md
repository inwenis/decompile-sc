# Task 027 — Run the game during tests without stealing the user focus

## Status

agent: 027
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task027 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task027-quiet-test-launch.
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

- Your inbox: `C:/git/decompile-sc/work/messages/027/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 027 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Unattended test runs must stop stealing the user's focus.** User, 2026-08-09: "a test just ran
and it was stealing my focus — the sc.exe was being moved to top of all windows, can we fix that?"
The tests currently raise StarCraft to the foreground on every run and yank the user's active window
away while they are working. Make an in-game test run without the game window grabbing focus or
input from whatever the user is doing.

## Context — and the tension you must respect

- **This is caused by a fix, not a bug, so do NOT just rip it out.** Task 022 established (with
  frame evidence, now in AGENTS.md "Posted mouse MOVES need the window foreground") that the game
  DROPS a posted `WM_MOUSEMOVE` while its window is not foreground — so drag boxes, the minimap
  click, and the Game Type dropdown silently do nothing. `Assert-ScWindowActive` in
  `tools/plugin/drive-game.ps1` was added to force the window foreground (AttachThreadInput, then
  verify, then throw) precisely so posted moves register. That fix took the harness from 25 lost
  assertions to 0. **If you disable foreground activation, you reintroduce that whole class of
  silent failures.** So the bar is: posted moves still register AND the user's focus is not stolen.
- **Investigate the mechanism before picking a fix — the cheapest option may already work:**
  - Does `AttachThreadInput` ALONE (sharing the input-state queue) make posted moves register
    WITHOUT `SetForegroundWindow`? Task 022 measured "ignored while not foreground" but may not have
    isolated attach-without-raise. If sharing the input queue is sufficient, the raise — the part
    that steals focus — can go. This is the first thing to test, because it is nearly free if true.
  - If a raise is genuinely required: run the game on a SEPARATE Windows virtual desktop, so it is
    "foreground" on its own desktop while the user works on theirs. `IVirtualDesktopManager` /
    the virtual-desktop APIs; move the game's window to a new desktop at launch, run the test there,
    the user never sees it come forward.
  - Other options to weigh: launch the game minimized-to-a-hidden-desktop; or restore the user's
    previous foreground window immediately after each activation (reduces but does not eliminate the
    flicker — weaker, but note it).
- **Whatever you pick must not break the nine in-game suites.** They all reach the game through
  `run-with-plugin.ps1` → `drive-game.ps1`, so the fix lands in the shared primitive and every suite
  inherits it. Re-run the drag-heaviest suites (`test-fanout-orders`, `test-selection-circles`) to
  prove posted moves still register after the change — that is the exact pair that went 25→0 when the
  activation was added, so it is the regression oracle.
- **Concurrency and coordination:** tasks 024, 025, 026 are HELD off in-game runs right now BECAUSE
  of this problem — they are the reason this is urgent. You are the one task cleared to launch the
  game, and you should do it on the virtual desktop / non-stealing path you are building, ideally
  when the user confirms the machine is free (ask the conductor to relay). When your fix merges, the
  held tasks are released onto it.
- Test discipline (task 023, merged): own folder `Maps\BroodWar\00-t027\`, `Select-ScBrowserMap`,
  `New-ScFixtureRun`, the shared launch lock. `run-ci-local.ps1` for the offline gate.

## Hard rules

1. Never modify, write to, or launch `C:\sc-install\Starcraft`. Working copy only.
2. Offline, single-player only. `StarCraft.exe` on disk stays byte-identical.
3. Never write live user state — AGENTS.md hard rule 5. In particular this fix must not change any
   GLOBAL Windows setting (foreground-lock timeout, focus-stealing-prevention registry keys under
   `HKCU\Control Panel\Desktop`) — that is user state, and process-scoped / per-window mechanisms
   are required instead.
4. Commit no game content, no binaries, no logs, no generated maps, no screenshots.
5. Do not merge your own PR.

## Acceptance criteria

1. An in-game test run completes WITHOUT the game window taking foreground or input focus from the
   user's active window — demonstrated, with a stated method for how "did not steal focus" was
   verified (e.g. the user's foreground window handle is unchanged across the run).
2. Posted mouse moves still register: `test-fanout-orders` and `test-selection-circles` both green
   after the change (the 25→0 pair), proving the drag/minimap/dropdown path did not regress.
3. No GLOBAL Windows setting changed (hard rule 3) — the mechanism is process- or window-scoped.
4. AGENTS.md "Posted mouse MOVES" section updated to reflect the new mechanism (foreground on its
   own desktop, or attach-without-raise, or whatever you land) so the next worker does not re-add a
   focus-stealing raise.
5. The other in-game suites + hooktest green; exe byte-identical; no stranded processes.
6. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/027-quiet-test-launch.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
