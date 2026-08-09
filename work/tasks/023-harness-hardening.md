# Task 023 — Harness hardening: folder-row computation, shared-suite folders, foreground activation

## Status

agent: 023
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task023 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task023-harness-hardening.
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

- Your inbox: `C:/git/decompile-sc/work/messages/023/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 023 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Make the in-game test harness stop losing runs to itself.** On 2026-08-09 two workers running
concurrently lost at least six runs to three distinct harness defects — one of them silently
producing confident nonsense (a suite ran a whole test against another task's map). The individual
fixes were made in-flight by whoever was bleeding at the time; this task consolidates them properly
and closes the ones nobody owned.

**Do NOT start until tasks 021 and 022 have merged** — this touches shared tooling both are editing.
Check with the conductor first; if either is still open, say so and wait.

## Context — the three defects, all diagnosed, none guessed

1. **Positional folder click.** Every suite opens the fixture folder with a fixed click on ROW 1
   (`Send-ScClick -X 117 -Y 140`). That was right when one `00-*` folder existed. Now each task has
   its own (`00-t021`, `00-t022`), so row 1 is whichever sorts first and everyone else opens the
   wrong folder.
   **Decided fix:** each suite computes its row from the FILESYSTEM — list `Maps\BroodWar\`, count
   the `00-*` folders sorting before its own — and then ASSERTS the opened folder contains its own
   fixture before proceeding. Deterministic, and it fails loudly rather than opening someone
   else's work. Same treatment for the map row inside the folder, which has the identical defect
   (`022-ghosts.scx` sorting before `combat.scx` is how the first incident happened).
2. **Shared suites hardcode the fixture folder.** `test-combat-death.ps1` is run by more than one
   task, so it cannot simply be pointed at one task's folder. Parameterise the fixture folder
   (default preserving today's behaviour) so any task can run it into its own.
3. **Posted `WM_MOUSEMOVE` is ignored while the game window is not foreground** — while posted
   clicks land either way. Task 022 measured this with frames. It is the suspected single root of
   THREE symptoms: the Game Type dropdown silently committing the wrong value, the minimap centring
   click failing intermittently, and `Send-ScDrag` selecting nothing (which cost
   `test-fanout-orders` 24 assertions and `test-selection-circles` 1 in one sweep).
   022 wrote `Set-ScWindowActive` (AttachThreadInput, then VERIFY — `SetForegroundWindow` alone is
   refused for a background process and lies about it). Consolidate it so EVERY input primitive
   that depends on a move — drag, minimap click, dropdown — goes through it, not just the dropdown.

## Second small item: the "CIRCLES stats line on detach" failure

Two tasks investigated this independently and their findings COMBINE into a full diagnosis —
do not re-derive it:

- **021** established it is not their code: the `STATS` line that precedes `GROUPSTATS` is
  missing too, so the whole of `ScFanoutLogStats` never reached the log — the cause is upstream
  of anything they added. They confirmed positively that three other logs from the identical
  build contain all three lines.
- **022** found the mechanism: the plugin's process-exit path switches the log to a **TRY-lock**
  and DROPS the line if another thread holds it; the observer thread had written 1.4 s earlier.

So: a benign log-write race at process exit that costs a real test assertion. Decide and
implement one of — make the exit path wait briefly for the lock rather than dropping, flush
before switching to the TRY-lock, or (weakest, needs justification) soften the assertion.
Whichever you choose, the test must still fail if the stats genuinely never ran.

## Small item inherited from task 022

**Name the Ghost's Cloak command-card button.** 022 could not drive Cloak: the key is not `C`
(it emits nothing even at full energy, so it is not the send-side gate either), and clicking
where the bottom-left button should be produced a frame reading **"Select Target"** — i.e. that
slot is a TARGETED ability (Lockdown), so the click armed something and issued nothing. One
keypress sweep against a working command card, with the emitted command id logged per key, names
it. This matters because the user's original report was about a cloaked Ghost specifically, and
022 could only answer the underlying mechanism, not that unit.

## The experiment this task owes

The third defect is **attributed, not confirmed**, for the drag/minimap symptoms. The confirming
experiment is one sweep of `test-fanout-orders` and `test-selection-circles` against the
foreground fix. Run it. If they go green, say so and record it as the confirmed root cause of all
three symptoms. **If they do NOT, say that too** — that result is equally valuable and stops the
next person treating foreground as the answer.

## Context — rules already settled, do not re-litigate

- AGENTS.md "Test fixtures: one folder per task" and "Shared test-fixture folder" — task-prefixed
  fixtures, delete only your own files on every path, refuse to start on a foreign `.scx`, re-check
  immediately before launch, remove your folder only when empty.
- `drive-game.ps1` KNOWN LIMITS: Ctrl/Shift/Alt keys are ACCELERATORS and cannot be driven by
  posted messages at all (`TranslateAcceleratorA` resolves modifiers against a key-state table
  Windows never updates for posted input). Post the `WM_COMMAND` the accelerator would send.
  Task 021 established this; do not rediscover it.
- Window-capture frames are offset from client coordinates by roughly +5,+32. A coordinate measured
  off a captured frame looks 32px too high when it was already correct. Task 021 nearly "fixed" a
  correct coordinate this way.

## Hard rules

1. Never modify, write to, or launch `C:\sc-install\Starcraft`. Working copy only.
2. Offline, single-player only. `StarCraft.exe` on disk stays byte-identical.
3. **Never write live user state** — AGENTS.md rule 5. `HKCU:\SOFTWARE\Blizzard Entertainment\*` is
   off limits (a worker zeroed the user's volumes there; they played silent for hours).
4. Commit no game content, no binaries, no logs, no generated maps, no screenshots.
5. Do not merge your own PR.

## Acceptance criteria

1. Folder row and map row both computed from the filesystem, with a loud assertion that the opened
   folder/map is the task's own. Demonstrated with two `00-t*` folders present simultaneously.
2. `test-combat-death.ps1` (and any other multi-task suite) takes its fixture folder as a
   parameter, defaulting to current behaviour.
3. Every input primitive that depends on a mouse move routes through the verified
   foreground-activation helper; it throws rather than proceeding if foreground cannot be obtained.
4. The confirming sweep is run and its result reported honestly either way.
5. All in-game suites green, or every non-green one attributed to a named cause with the
   distinguishing experiment stated.
6. `scripts/run-ci-local.ps1` passes; exe byte-identical; no stranded processes; no fixture folders
   left behind.
7. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/023-harness-hardening.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
