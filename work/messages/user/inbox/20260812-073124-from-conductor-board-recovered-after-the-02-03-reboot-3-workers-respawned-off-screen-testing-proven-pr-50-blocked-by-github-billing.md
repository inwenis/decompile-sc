---
from: conductor
to: user
sent: 2026-08-12T07:31:24Z
subject: Board recovered after the 02:03 reboot: 3 workers respawned, off-screen testing PROVEN, PR #50 blocked by GitHub billing
---

Board is back up after the night. Numbered, newest facts first.

## 1. The reboot — being investigated right now, verdict not in yet

The machine booted at **02:03:01Z** (~04:03 your time). All four workers died 3-4 minutes
before that (last heartbeats 01:58:59Z - 01:59:14Z), which is consistent with them being
killed BY the restart rather than causing it — but that is a shape, not a cause, so I have
a fable-model investigator on the Windows event log now: Kernel-Power 41, BugCheck 1001,
**User32 1074** (the event that names the process that requested a restart, which is the
one that answers your fear directly), Windows Update, display-driver TDR, thermal/battery.
It is also grepping all repo tooling for `Restart-Computer` / `shutdown.exe` /
`Stop-Computer`.

I will send you its verdict as its own message the moment it lands. What I can already say:
nothing in this repo's tooling is *supposed* to be able to reboot the machine, and the one
worker doing anything exotic that minute (043, creating a Windows desktop and launching the
game onto it at 01:59:05Z) is exactly what the investigator is told to rule in or out.

## 2. Your screenshot rule — taken, with one honest constraint

Standing rule accepted: a UI claim without a picture is not a claim. Applied from now on to
every feature I report to you.

The constraint, and it is a project hard rule you set, not my preference: **game frames can
never go into the repo or a PR** (hard rule 1 — `pr-image` pushes to a branch in this repo,
and a game frame reproduces Blizzard artwork). So the picture reaches you as a **file on
your own disk** plus the exact path, e.g. `C:\sc-work\logs\042-frames\...png` — you open it
locally, nothing is published.

Unless you tell me otherwise I will also have the report **open the frame in your image
viewer** when I hand you a UI claim, so "show me" costs you no clicks. Say the word if you
would rather it stayed a path.

I have told 039 (the queue-indicator fix — your "5th slot draws garbage" bug) and 041 to
capture a frame for every visual state they claim, and the `page i/j` indicator is on that
list.

## 3. Fleet recovered — three workers respawned and already reporting

The reboot killed all four; their transcripts did NOT survive, so each got a written
briefing of what its own worktree holds before respawning.

| task | what it is | state now |
|---|---|---|
| 039 | the 5th-slot garbage + group text behind the icons (your bug report) | respawned, reading back 4 commits + uncommitted work |
| 041 | randomized conformance testing (your "12 units, charged for 12") | respawned, harness on disk is near-complete and has NEVER been run |
| 043 | run tests off-screen so your screen stops being taken | respawned, **verdict already in — see 4** |
| 042 | the selection-array fix | finished before the reboot, PR open — see 5 |

## 4. 043: your screen problem is SOLVED in principle, measured this morning

**Posted input drives the game across desktops.** Both arms, same script, same oracle (the
engine's own active-dialog list read out of memory, not a pixel hash):

- visible desktop: `MainMenu` -> `Delete,MainMenu`, 0 failures
- invisible desktop `sc-043-14432`, monitor showing your normal desktop: same transition,
  0 failures, **nothing appeared on your screen**

So the whole suite can move off-screen. 043 is now converting the suites. One open risk it
named: `GetForegroundWindow()` returns 0 on an invisible desktop, which may break the one
primitive allowed to raise (the game-type dropdown) — it is measuring that next, and the
first suite it converts does not use it.

## 5. PR #50 is reviewed and green LOCALLY — and blocked by your GitHub billing

Task 042 (`fix(sc_upgrades): read the SIMULATION's selection, not the CLIENT's`):
https://github.com/inwenis/decompile-sc/pull/50

I reviewed it against all five acceptance criteria myself rather than taking the worker's
word, and ran the local gate:

- the index arithmetic matches the engine's own operands (`playersSelections` 0x006284E8,
  row = activePlayerId, stride 12) and is identical in shape to task 038's merged fix
- the new hooktest has real teeth: it sets the two arrays to DIFFERENT buildings, which the
  old code answers wrongly and the new code answers right
- `scripts/run-ci-local.ps1` on the branch: **PASS** — 77 Pester tests, hooktest 0 failures
- real-game run: 0 failures, and 037's indicator still draws (`text="+3 upg" ink=608`
  against a positive control `refInk=1330`)

**But GitHub Actions has not run a single job since 01:39Z**, on any branch including main:

> The job was not started because recent account payments have failed or your spending limit
> needs to be increased.

That is billing, not code. `merge-task.ps1` refuses to merge without green checks, by design,
so **nothing can merge until you fix that** — and 039, 041 and 043 are all heading toward
PRs behind it. I am sending you a separate one-question message with the options.
