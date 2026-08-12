# decompile-sc — rulebook

## What this repo is

Personal, private reverse-engineering research on StarCraft. Primary target:
the 1.16.1-era binary (richest public prior art — BWAPI offsets, community
struct maps, prior decompilation efforts). Deliverables are DOCUMENTATION
and TOOLING, not redistributed game content.

## Project hard rules

1. NEVER commit game binaries, MPQ archives, extracted assets, or anything
   derived from them that reproduces game content. The repo tracks findings
   and tooling only. `.gitignore` blocks the common extensions; the rule
   covers everything the ignore patterns miss.
2. The local game copy lives at `game/` (gitignored) and is READ-ONLY to
   workers. Need to patch a binary? Copy it into your worktree or
   `work/scratch/` first.
3. Never point a modified binary at Battle.net or any online service.
   Offline and single-player only.
4. Every claimed address/offset/struct must carry evidence: how it was found
   and how it was verified. No guessed offsets in `research/`.
5. NEVER write to live user state outside the repo and the working copy —
   registry keys, `%APPDATA%`, Documents, the desktop. The user's machine is
   not a test bench. Specifically: `HKCU:\SOFTWARE\Blizzard Entertainment\*`
   holds their real game settings (2026-08-08 incident: `New-Item -Force` on
   an existing key DELETES AND RECREATES it — 22 settings wiped, restored
   from a lucky pre-existing dump, MRU list partly lost). Prove any
   state-touching mechanism against a throwaway key/path first, and prefer a
   process-scoped mechanism over persistent user state whenever both work.
   Deployment targets the user chose (the deploy dir, a desktop shortcut) are
   the exception — write those, but never destructively (see `tools/deploy.ps1`
   player-data rules).
6. `C:/git/conductor` and `C:/git/conductor-task*` are ANOTHER LIVE SYSTEM
   (a separate orchestrator with ~25 in-flight agents and real user
   messages). NEVER read, modify, `cd` into, or run git/gh against them from
   this repo — touching them is a data-loss incident. Everything this repo
   needs from there is already ported into `scripts/`/`config/`; if
   something seems missing, ask the user. (Sole exception: `./run.ps1`,
   which the USER launches to serve the Agent Console UI.)

## A player-input feature is unproven until the wire has been watched (2026-08-09, task 025)

If a feature begins with a player input — a click, a hotkey, a button on the command card —
an offline proof of your logic can be confidently, completely wrong. The client may never
send the command you are handling.

Task 025 built over-cap production queueing against a receive-side handler, and every
offline test passed. In game the queue never grew: pressing Train twelve times put exactly
FIVE commands on the wire and then nothing, because the client greys its own button out and
refuses to send a sixth. The handler was waiting for a command that does not exist. The
whole design had to be inverted (keep the engine's ring below its cap so the button stays
lit) — and only a real run showed it.

So: for anything that starts with player input, watch the engine's command funnel
(`queueCommand` 0x00485BD0) in a real game BEFORE trusting your handler. Offline tests
prove your code does what you meant; only the wire proves the game asks it to.

## Assert the ENGINE'S OWN RESULT, not your bookkeeping (2026-08-10, task 029)

"N items are in my queue" is a claim about the plugin. "The engine's level array went up" is
a claim about the game. Only the second one is the feature. A suite that stops at the count
passes for a version that queues things the engine will later refuse.

Task 029 queued upgrade levels by asking the card's condition whether the next level may be
researched — with the level array still at its CURRENT value. Requirements in this engine are
PER LEVEL (requirement opcode 0xFF1F reads the player's level and jumps to that level's own
block), so the answer returned was level N's answer to a question about level N+1. The card
duly offered Infantry Weapons 2, and the engine's own gate refused it at promotion because
level 2 needed a prerequisite building the fixture did not have.

Nothing was lost — the promotion-time gate is the backstop and it worked — but the UI had
promised something it could not deliver, and **the queue-length assertion passed the whole
time**. It was caught only because the suite also read the engine's own level array.

So: for any feature that makes the engine do something, assert the thing the ENGINE changed —
its arrays, its unit fields, its resource globals — not merely that your own structure holds
the right number of items. And where a plugin evaluates an engine predicate on the engine's
behalf, evaluate it in the state the action will ACTUALLY run in, not the state you are in
when you ask.

**The UI shape of this, 2026-08-11, task 033: a read-back of your own buffer is not a
read-back.** `sc_hudrow` spliced a page indicator, wrote `"36 units 13-24 (2/3)"` into it, and
`test-hud-row.ps1` asserted that string — out of the module's own buffer. Green for weeks, and
NOTHING WAS EVER DRAWN: the engine's string draw refuses when `top + fontHeight > clip.bottom`
and the control's box was nine pixels tall. The user found it by asking how to page. The fix
for the ORACLE is to count what the engine actually left behind — task 033 counts non-background
bytes (`ink`) in the dialog's own 8-bit surface inside the control's bounds, with the same count
over a known-drawn control as the positive control, so `ink=0` cannot be confused with a blind
probe. That is a read-back; asking your own buffer what you put in it is not.

**And a check that fails at RANDOM is worth as little as one that cannot fail** (same task): the
fifth-icon assertion passed one run and failed the next because the observer thread sampled
between the plugin filling a slot and the engine's layout re-greying it, microseconds later,
inside one driver call — invisible to the player, who only ever sees the frame. Both times the
fix was to ask the thread that OWNS the data: snapshot on the game thread at end of frame for
frame state, keep the async walk for the building's own memory, which the frame path never writes.

## Your DIAGNOSTICS are under the same rule as your assertions (2026-08-10, task 030)

The "a check that cannot fail is worth nothing" rule applies to the lines you print while
debugging, not only to the ones the suite asserts on. A wrong number in a log is worse than
no number, because you will reason from it.

Task 030 added `lit=%d` to a format string and did not add the argument. The run printed
`lit=4`, which read as "the detour allowed the button four times", and an hour went into
explaining why the gate returned 0 — when the gate had never been called at all. The real
state was ZERO log lines from that function.

So, for any diagnostic you are about to trust:

- A count you print must be a count something incremented. Check the format string has an
  argument for every specifier — a missing one prints stack garbage, not a zero.
- Prefer printing WHICH BRANCH was taken over printing that a branch was taken. Task 030's
  fix was to count all seven exit terms (off / count<=1 / not-a-train-button / bad-unit /
  not-a-group / type-mismatch / handled) and print them together, so "it refused" always
  names the test that refused.
- "No log line appeared" and "the function returned false" look identical in a quiet log.
  Log entry as well as outcome, at least once, so absence is distinguishable from refusal.

## An enumeration that scanned for a NAME is not exhaustive (2026-08-11, task 034)

Two failure modes of "I searched the binary and found them all", both met in one task.

**1. A routine that is HANDED a pointer never names it.** Task 034 enumerated framebuffer
writers by scanning `.text` for the pointer `0x006CEFF4` and called that exhaustive. It is not:
`FUN_004800A0` writes the framebuffer through a pointer passed in a register, sits 1405 bytes
from the nearest reference to it, and is UNROLLED — holding the pitch as fourteen displacements
`[ecx + k*640]` and `[ecx + k*640 + 4]`, of which exactly ONE spells 640. Fifteen instructions
no pointer scan could reach.

So sweep for the SHAPE of the arithmetic — `k*pitch + d` — not for the pitch and not for the
pointer. `tools/renderer_pitch_sweep.py` does this. Note that searching multiples alone finds
only half of them (the `+4` twins are not multiples of anything), and half a fix in a rendering
path renders rather than crashes.

**2. A disassembly sweep that stops early reports ZERO and looks like a clean bill of health.**
Capstone halts at the first byte it cannot decode; the first version of that sweep therefore
covered only the bytes before the first jump table — about 3% of `.text` — and printed "nothing
found". A tool that scans 3% and reports zero hits is the worst possible output, because it is
indistinguishable from a correct all-clear. Make such sweeps resume past undecodable bytes AND
report the fraction of the section they actually covered.

**3. And the same task's oracle was too COARSE rather than wrong.** It reported stage 0 as
"pixel-identical"; measured at full resolution, 586 of 307200 pixels differ — animated doodads
caught at different phases, invisible to a check that sampled every second pixel against a
90%-per-row threshold. The fix was to assert on SHAPE, not count: a wrong pitch damages whole
ROWS across the full width, while animation differs in isolated blobs spanning no row. Assert
the thing that distinguishes damage from noise, and report the noise floor beside it rather than
asserting against zero.

## A random suite must report the coverage of its SEAM, not only its verdict (2026-08-12, task 041)

A generated test can be green because the feature works, or green because the run never got
anywhere near the thing it was built to break. Those two results print identically, and the
second one is worse than no test — it is a passing regression check standing guard over a bug.

Task 041's randomized harness was pointed at `59aa50b`, the commit BEFORE task 038's fix, with a
seed whose plan contained several multi-building bursts. It reported **`PASS 94 checks, 0
failures` against the very build whose bug it was written to find.** Nothing had gone wrong
mechanically: the run's own `indicator` episode filled one building to the plugin's cap, the
headroom check then clamped every later GROUP burst to two or three presses, and **below the
engine's five slots a plugin with 038's bug behaves exactly like a correct one** — the rings
never fill, so the client never greys the Train button, so nothing diverges. The seam was never
touched, and no line of the output said so.

So: name the seam your suite exists to test, COUNT the episodes that actually reached it, and
print that count beside the verdict every time. When it is zero, say what that means rather than
leaving it to be inferred — task 041 prints:

```
COVERAGE  NO episode pushed a MULTI-BUILDING selection past the engine's 5 slots.
          A run that never does that CANNOT detect task 038's class of bug, whatever its verdict says.
```

The same task's other half, and it is the same disease: **it printed `PASS 13 checks, 0 failures`
for a run that executed NO EPISODES AT ALL.** An exception right after the fixture step unwound
past the summary block, which duly reported the 13 checks that had run, while `| Tee-Object` — the
transcript pipe every run of it uses — swallowed the non-zero exit. A verdict that does not depend
on reaching the end of the work is not a verdict. The fix is structural rather than careful: the
run records that it finished its episode loop, anything else prints `INCOMPLETE` (its own word,
never `PASS`) with the episode count on it, and the exception is caught and recorded as a failure
rather than allowed to unwind. It has since caught three real aborts, including a launch that
loaded the wrong map off a shifted browser row.

And the corollary for the seed: **choose it for the seam and say that you did.** Task 041's teeth
test uses seed 47 because its episode 1 is an 11-press burst across two buildings and its episode
2 a 9-press group recall, both against empty queues — picked from the offline plan generator with
no game involved. A seed chosen because it produced the desired result is seed-shopping; a seed
chosen because it reaches the seam, stated in the PR, is a fixture.

## Take the ADDRESS from the engine's own instructions, not from the global next door (2026-08-12, task 038)

When a plugin re-implements an engine predicate — "which unit is this command about", "may this
be built here" — the arithmetic has to come from the engine's own code, operand by operand. A
global of the right shape and the right name, sitting next to the right one, will agree with it
for as long as your tests are simple.

Task 025 re-implemented `cmdrecvTrain`'s "exactly one unit selected" gate as
`activePlayerSelection[0] != 0 && [1] == 0` and called it "the same test without calling into the
engine". The test was right; the ARRAY was wrong. `getActivePlayerNextSelection` (`0x0049A850`)
walks `playersSelections` (`0x006284E8`), row `activePlayerId` — and the two arrays **abut**
(`0x006284B8 + 12*4 == 0x006284E8`), are both `CUnit*[12]`, and hold the same thing whenever the
player has one building selected. Which is every case either suite had, so it passed everywhere
for two tasks.

It broke the moment a second feature made the two disagree on purpose: task 030's fan-out replays
one Select+Train per building, so the SIMULATION holds one building while the CLIENT still holds
the group. Reading the client's list, the plugin answered "not a single building" for every
replayed Train, held nothing back, and every ring filled to five — the user's report, *"can't
queue more than 5 units per building when multiple buildings are selected"*.

So: dump the engine function and read its operands. `MOV EAX,[0x0051267C]` / `LEA EAX,[EAX+EAX*2]`
/ `MOV EAX,[ESI*4 + 0x006284E8]` names the base, the row and the stride, and none of the three is
a judgement call. Where the plugin then evaluates that predicate, evaluate it in the state the
action will ACTUALLY run in — the same rule task 029 wrote about per-level requirements, one
layer down.

And the counterpart on the diagnostics side: this cost a whole in-game run to see, because "the
plugin is holding nothing" and "the plugin was never handed a building" print the same zeros.
Count the detour's exits, not just its successes (`trainSeen` / `trainNoUnit` in `PRODQSTATS`) —
the task-030 rule about naming the term that refused applies to the entry as well as the verdict.

## Absence assertions must first be proved positive (2026-08-09)

An assertion that something is ABSENT is worth nothing until the same pattern has been shown to
MATCH somewhere it should. Two suites gated "the stock arm installed no hooks" on a string the
plugin never logs (`HOOK install`, when the real lines are `HOOK <name>: installed at ...` and
`HOOK: n/n installed`). The check could not fail, and a research doc cited it as the reason the
control was trustworthy.

So: prove the pattern positive against a log where the thing DID happen, then require it absent
where it should not have. Pair every absence check with a positive one — "the ability fired in
this arm" alongside "nothing was interrupted" — or a silently broken run reads as a clean result.

## Read a dialog's CONTENT from memory; never hash its pixels (hard rule, 2026-08-09, task 026)

**A frame hash answers "did any pixel change". That is not the question, and it is not stable
across sessions.** Task 023 gated the whole Ghost-cloak result on two region fingerprints of the
command card and concluded that researching the tech "DOES draw a different command card". It does
not: reading the card out of process memory shows both fixtures holding the same nine slots, the
same buttons, in the same states — and on the next session both fixtures hashed to the *same*
value, the one 023 had recorded for the control. Two sessions of work were spent on a conclusion a
pixel hash had invented.

So: when a claim is about what a dialog **holds** — which button, which slot, enabled or greyed —
walk the dialog and read the fields. The engine's UI is ordinary heap data; `sc_card`/`sc_hudrow`
show the shape, and a read-back needs no hook and works in `-Mode observe`. Keep frame captures for
corroboration and for the human, never as the oracle.

The same rule caught a second thing the same evening: a tool that verifies its own write with its
own indexing verifies nothing. `make_test_map.py` wrote PTEx tech-major and read it back tech-major
while the engine reads it player-major, so its validator printed
`PTEx: player 0 has researched 10(...)` for maps on which player 0 had researched nothing. **Check
a fixture in the engine's memory, not in the generator's read-back.**

**The point is the ORACLE, not the outcome.** Once that fixture bug was fixed, the two slot tables
really did differ — slot 7 greyed without the tech, enabled with it. The read still wins, because
it says *which slot and in which state*, which is what a hash cannot say however it comes out.

**And the rule applies to itself: a read is only an oracle if the act being measured cannot change
it.** Task 026's probe named the Cloak slot by its Cloak *action*, then cloaked the Ghost — which
flips that slot to its Decloak face — and duly reported "no Cloak button on the card". A false
negative manufactured by its own success. So take the read BEFORE the action as well as after, and
make the verifier something other than the thing that acts. This project has now met that shape
five times over; `research/command-card.md` §6.4 tabulates them.

**One more, from the same task, about measurement windows rather than reads.** When a target
building died inside a two-second measurement window, every unit shooting it dropped to idle at
once — bit-for-bit the signature the experiment was looking for, and three times more likely in the
treatment arm than the control arm *because the feature under test worked*. A confound correlated
with the arm, pointing at the conclusion, is the one to design out rather than tolerate: fix the
fixture so it cannot happen, AND gate the run so a window in which it happened cannot be published.

## Never click a map-browser row by number (hard rule, 2026-08-09, task 023)

**`Select-ScBrowserMap` walks the browser. Nothing else does.** It scrolls the list to a
known top, computes every row from the filesystem, and makes the browser prove the row it
clicked was a map. A hardcoded `-X 117 -Y 140` is the defect that cost six runs in one day,
and it has three levels — the fixture folder's row, the map's row inside it, and the row of
`[Up One Level]`, which sorts ALPHABETICALLY AMONG THE FOLDERS and therefore moves when any
task creates a fixture folder. That third one broke a suite that generates no fixture and
shares no folder, so "I don't use the shared folder" is not an exemption.

The list also opens ALREADY SCROLLED, which is why a computed row is not enough on its own
and why the sync comes first. Details and evidence: the block comment above
`Get-ScBrowserListing` in `tools/plugin/drive-game.ps1`.

## Test fixtures: one folder per task, one NAME per suite (hard rule, 2026-08-09)

**Generate into `Maps\BroodWar\00-t<NNN>\`, your own folder — never the shared
`00-testmap`.** This removes the contention in both directions instead of racing for it.
Suites take `-FixtureDir` for exactly this: more than one task runs some of them, so the
folder is the caller's choice, not the suite's.

**Name the fixture after the SUITE, not the task** (`burrow-fanout.scx`). Two suites
generating `lurkers.scx` made "delete only your own file" undecidable between them and
blocked a run outright.

**Declare every fixture a run will create, up front** (`New-ScFixtureRun`). Ownership is
per-run, not per-file: the old one-filename rule counted a suite's own earlier fixture as
foreign and made it wait for itself. Declaring is not softening — anything outside the
declared set is still foreign, and refusing is still the answer.

Remove the folder at the end of the run, and only if it is empty — an empty folder of yours
still pushes every entry below it down a row for everyone else, and only six rows are
visible at once.

The rules below still apply INSIDE your own folder (they are what caught the incidents):

## Shared test-fixture folder (hard rule, 2026-08-09 incident)

Every in-game suite generates its map into ONE shared folder in the working copy, and the
map browser is clicked **by ROW, not by name** — so a file another worker drops in there
changes which map YOUR test loads. On 2026-08-09 task 021's run played task 022's fixture
(36 Ghosts where it places Lurkers) and then recursive-deleted the folder.

Rules, all three, no exceptions:

1. **Name every generated fixture for its suite** (`burrow-fanout.scx`) and declare it to
   `New-ScFixtureRun`, so "mine" is decidable from the filename alone.
2. **Delete only your own declared files**, on every path including `finally`. Never
   `Remove-Item -Recurse` that folder.
3. **Refuse to start if any `.scx` you did not declare is present** — whether or not a game
   is running. Process-liveness is NOT a sufficient test: the other worker's run may begin
   seconds after yours generates its fixture.
4. **Re-check immediately before the browser walk**, not only at generate time. The
   folder can be cleared or added to in between — task 022 lost a run to exactly that. Throw
   with the cause named rather than playing whatever is there.

Rule 3 is what prevents the silent failure — playing someone else's map produces internally
consistent nonsense, which is worse than a crash.

## Foreground: only ONE primitive may raise (hard rule, 2026-08-09, task 027 — reverses 022/023)

**The rule has three halves and you need all of them. Reading one alone re-opens a real bug.**

1. **Posted mouse MOVES, clicks and world DRAG-boxes do NOT need the foreground.** Nothing
   in the harness may raise the window for them. This is the half that reverses 022/023.
2. **A DROPDOWN pick DOES** — `Send-ScDropdownPick` is the one and only place in this repo
   allowed to raise, it does so for the length of one pick, and it hands the foreground
   back afterwards. Delete that and the Game Type pick silently stops taking. Details at
   the end of this section.
3. **The GAME raises itself at launch, and the harness hands that back too** (issue #30).
   Nothing in the harness asks for it — the game activates its own window when it creates
   one — so the fix is symmetric with the pick: record, then restore. Half 3 below.

Half 1 used to be stated the other way round. It was wrong, and the wrong version cost the
user their focus on every unattended run — the complaint that opened task 027.

Two kinds of evidence:

- **Static.** The window procedure (`StarCraft.exe` `FUN_004d1d70`, Ghidra) handles
  `WM_MOUSEMOVE` with three unconditional stores and a return — no foreground check, no
  active check: `DAT_006cddc0 |= 1; _DAT_006cddc4 = lParam & 0xffff; _DAT_006cddc8 =
  lParam >> 16;`. The binary's only `GetForegroundWindow` call site (`0x004eddf0`) is a
  diagnostic.
- **Live** (`tools/plugin/probe-quiet-input.ps1`, one launch). With the USER'S window
  holding the foreground throughout, a posted move onto the main menu's Single Player
  button changed that button's region (`FF975A03A546737B` → `271D215ABFB1EF45`). Then
  raising the game put it straight BACK to `FF975A03A546737B`: activation re-syncs the
  game's cursor to the physical mouse, so the raise **destroys** the posted position it
  was supposed to enable.

Activation is worse than useless here. The same `WM_ACTIVATEAPP` case (`case 0x1c`) runs
`0x004d1750` and `0x00421730`, which call `SetCursor`/`GetCursorPos`/`SetCursorPos` and
**`ClipCursor(window rect)`** — every raise confined the user's real mouse to the game
window.

What 022 actually measured was a DRAWING difference, with a frame oracle: the game gates
drawing on activation (`0x0041d710` returns 0 while `DAT_0051bfa8`, written by that same
`WM_ACTIVATEAPP` case, is 0). Under the windowed-mode helper every suite injects, drawing
does NOT stop — the probe fingerprinted the animated main menu 3 s apart with the window in
the background and got two different frames — so the pixel oracles (browser rows,
`Set-ScGameType`) work in the background too.

So:

- `Assert-ScWindowActive` no longer touches the foreground. It refuses to post into a dead
  or **MINIMISED** window, which is the real hazard (task 012 probe 2), and that is all.
- `Set-ScWindowActive` still exists, opt-in only: `-RaiseWindow`, or `$env:SCDRIVE_RAISE=1`
  for a human who wants to watch a run. **No suite may set it.**
- Do not "fix" a flaky input by activating the window. It will not be the cause, and it
  will steal the user's focus and trap their mouse while the run lasts.

### Half 2: the dropdown, the one place a raise is allowed

**Measured, not assumed: `Send-ScDropdownPick`.** A menu dropdown is a press-and-hold
control and the game calls `SetCapture` on button-down (`0x004d1a76`); Windows grants the
mouse capture only to the FOREGROUND window. `probe-quiet-dropdown.ps1` ran all three arms
on the Create Game screen: background = pick did not take, background + `AttachThreadInput`
+ `SetActiveWindow` = pick did not take, foreground = took on the first attempt. So that
primitive raises for the length of ONE pick and then **hands the foreground back** to
whatever had it (which also makes the game release its `ClipCursor`). Cost: about two
seconds during the menu walk of the three suites that call `Set-ScGameType`, instead of the
whole run. A world drag-box is also a held-button walk and needs none of this — so this is
the dialog control, not held buttons in general.

### Half 3: the LAUNCH borrows too, and gives it back (issue #30, task 035)

The game activates its own window when it creates one, and until 2026-08-11 nothing handed
that back. On a busy desktop it looked like a few seconds of flicker; on an idle one the
game simply kept the foreground for the whole run (task 029 measured 72 s of a 72-second
run, and what looked like a "hand back" was the process exiting).

So a worker launch now records the foreground window immediately before `CreateProcess`
and restores it once the game's window exists — `tools/plugin/sc-foreground.ps1`, called
from `run-with-plugin.ps1`. Measured before and after, same machine, same minute, one
launch each (in-process sampler, 150 ms, `C:\sc-work\logs\035\fg2-*.txt`):

| | game holds the foreground | how it ended |
|---|---|---|
| before (`-NoForegroundRestore`) | 09:27:07.5 → 09:27:35.7, **28.2 s of a 28 s run** | the game was CLOSED |
| after (default) | **~4 s**, then handed back | handed back to the pre-launch window, which then kept it for the rest of the run |

**The residual is structural, and it is worth knowing why.** Stamping the launch stages
against the sampler, one launch:

```
T+5.28  scinject starts the game
T+5.53  the game's window creation takes the foreground
T+9.60  scinject RETURNS -- the first instant run-with-plugin.ps1 runs again
T+12.19 check-game-windows
```

`scinject.exe` blocks for its own settle, so nothing in PowerShell executes between T+5.5
and T+9.6: **~4 s of the hold cannot be reached from here at all.** The restore therefore
fires the moment scinject returns (the game's window already exists — scinject has been
through `WaitForInputIdle`), with a second attempt after the health check as a safety net.
Shortening it further would mean changing scinject's injection timing, which is not a
foreground problem.

**Workers only.** The gate is `$env:AGENT_TASK` — never set for the user's own shortcut —
plus `-NoForegroundRestore`, which `tools/deploy.ps1` bakes into the deployed launcher.
Someone who double-clicked their game wants to see it. `$env:SCDRIVE_RAISE=1` turns the
restore off too, for a human watching a run.

### How to check a run did not steal focus

`tools/plugin/watch-foreground.ps1` samples `GetForegroundWindow()` every 250 ms and prints
one line per CHANGE, exiting non-zero if any StarCraft window was ever foreground. Run it
alongside a suite; do not claim "it did not steal focus" without it.

**Always check a trace's pids against the pid the launch printed.** Task 035 saw two traces
name StarCraft pids that were not the game it had just launched, and briefly concluded the
tool was fabricating them under
`Start-Process -WindowStyle Hidden -RedirectStandardOutput`. It is not: run head to head
against an in-process sampler through one launch, that exact invocation agreed on the
window handle, the pid and the second. What the odd traces were actually showing is the
thing the pid check is for — **another StarCraft on the machine**, which on a multi-worker
box is a competing launch bouncing off the game's single-instance check. The reading was
right and the assumption "the StarCraft in my trace is my StarCraft" was wrong. Nothing any
earlier task concluded with this tool is affected.

What a correct run looks like: **one borrow-and-return pair for the LAUNCH** (~6 s, above),
then for the six suites that never pick a game type, nothing else — `test-fanout-orders`
and `test-selection-circles` (the pair 022/023 cited) both went 0 failures with the user's
window keeping the foreground for the rest of the run. For the three that do pick a game
type, one further pair around each pick (measured: foreground at 22:03:39, back to the
user's window at 22:03:43). Anything else is a bug.

Note what the launch fix does for the pick: `Send-ScDropdownPick` returns the foreground to
whatever held it *before the pick*, and on an idle desktop that used to be the game itself,
because the launch had taken it and never given it up. With the launch handing back, the
pick's hand-back lands on the user's window, which is what it was always meant to do.

## A test run happens on an INVISIBLE DESKTOP (2026-08-12, task 043)

**Default: `run-offscreen.ps1`, not the suite directly.** The user's ask that opened
this — *"can we setup a vm so you can run tests there so my screen doesn't get messed
up?"* — is answered without a VM. `CreateDesktop` makes a second desktop object inside
the existing login session (the primitive Windows itself uses for the UAC prompt); the
suite is started as a child process BORN on it, `run-with-plugin.ps1` passes that name
to `scinject.exe --desktop`, and nothing the run draws ever composites to the monitor.
Nothing is installed and nothing survives the run.

```powershell
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/test-selection-circles.ps1
./tools/plugin/run-offscreen.ps1 -Visible -Suite ./tools/plugin/test-selection-circles.ps1
```

`-Visible` is the debugging run, and it is the SAME code path — same child script, same
`CreateProcess`, same suite arguments, only the desktop name differs. Never grow a
separate watch mode; a path that only runs when a human is looking is how you get a bug
that only exists when nobody is.

**The suites are unmodified, and must stay that way.** A process gets its desktop at
creation, every thread inherits it, and `EnumWindows` is desktop-scoped — so
`Get-ScGameWindow`, `check-game-windows.ps1` and `close-game.ps1` follow the game across
untouched. There is no list of primitives to make desktop-aware and therefore no list to
be one item short of. (The other design is not available anyway: `SetThreadDesktop`
returns `ERROR_BUSY` for a thread that already owns a window, which PowerShell's main
thread does before your first line runs.)

Measured, same suite, same assertions, one flag apart (`test-selection-circles.ps1`,
`time-suite.ps1` wall clock): **75.0 s off-screen vs 75.2 s visible**, identical
assertion-by-assertion including the same one pre-existing failure. `watch-foreground.ps1`
across the off-screen run: no StarCraft window ever foreground. Isolation costs nothing.

**`sc-launch-lock.ps1` still serialises every launch — do not "improve" that away.**
StarCraft is single-instance PER MACHINE regardless of desktops. Invisible desktops fix
VISIBILITY of however many runs happen; they do not buy concurrent games.

### The one input that cannot work off-screen: a dropdown pick

Windows has one foreground window and it belongs to the desktop receiving input, so a
window on an invisible desktop can never hold it — `GetForegroundWindow()` reads 0 there
all run. `Send-ScDropdownPick` needs the foreground (the game calls `SetCapture` on
button-down; see "Foreground" half 2), so it cannot succeed there. Measured, not
reasoned: `probe-quiet-dropdown.ps1` through `run-offscreen.ps1` failed ALL THREE arms,
including arm C, the foreground control that passes every time on the visible desktop.

This bites rarely, because `Set-ScGameType` reads the combo out of the engine's dialog
list and skips the pick whenever the value already matches (issue #29) — `test-stim-fanout`
runs off-screen with 0 failures on that path. When a pick IS needed the run **throws and
names the desktop as the cause**; it never silently runs a lesser test. The fix is one
flag: re-run with `-Visible`.

The launch-time foreground dance (`sc-foreground.ps1`, half 3 above) self-neutralises
off-screen — there is no foreground to record or hand back, and the launcher says so.
Leave it in place: it is still what protects a `-Visible` run.

## The in-game tips dialog is dismissed by ITS OWN button, never by a fixed point (task 027)

`Tips_Dlg` is a normal engine dialog, and every suite used to close it with an
unconditional click at `(200,261)` — no check that it was there, no check that it went.
Use `Dismiss-ScTipsDialog -Hwnd -LogPath`: it waits for the dialog in the engine's own
active-dialog list (the plugin's `DIALOGS` log line, list head `0x006D5E34`), computes the
OK button's centre from that button's own bounds, clicks it, and **throws if the dialog is
still up**. A tip dialog left open eats every later click in the run.

Never turn tips off through `HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft` — that is
live user state (hard rule 5) and the dialog's own "Show Tips at Startup" checkbox writes
it. Dismiss for this run; leave the user's setting alone.

## Screenshots vs hard rule 1 (settled)

The global rule "visual change → screenshot → `pr-image`" does NOT apply to game frames.
`pr-image` pushes to a branch in this repo, and a game frame reproduces game artwork,
which hard rule 1 forbids. Hard rule 1 wins — always, without asking.

Instead: prove visual claims with the in-process read-back oracles (`CIRCLES show:`,
`HUDROW show n=… page=…`, `UNITSTATE`), describe the appearance in the PR body, and keep
frames on the gitignored diagnostic path for the conductor or user to open locally.
Workers have correctly declined the screenshot twice (tasks 016, 021); this section exists
so nobody has to weigh it a third time.

**But the frame is now MANDATORY on disk — user standing rule, 2026-08-12T07:28Z:**
*"when you tell me about ui elements you show me with screenshots - like `page i/j` - show
me a screen shot of this. same with all other features you're telling me about - show me
with screenshots"*. Both halves hold at once, and they do not conflict:

- Every visual claim a worker makes — in a PR body or a message — carries a PNG of that
  exact state, captured through the suite's `-CaptureFrames` path into
  `C:\sc-work\logs\<NNN>-frames\`, named for the STATE rather than a counter, before and
  after for anything claimed fixed, one pair per distinct case.
- The path is what travels. Never the image: no `pr-image`, no committed frame, ever.
  The conductor hands the user the paths and they open them locally.
- The read-back oracle is still the oracle; the frame is for the human. A frame is never
  asserted on (see § "Read a dialog's CONTENT from memory"). An oracle with no frame is no
  longer reportable to the user; a frame with no oracle never was evidence.

## Layout

- `work/` — orchestration DATA.
  - `work/tasks/` — task files (`_template.md`, `NNN-<slug>.md`).
  - `work/reports/` — task reports (`NNN-<slug>.md`).
  - `work/messages/<agent-id>/{inbox,read}/` — agent messaging. NEVER delete
    or overwrite anything under `work/messages/` (2026-07-17 data-loss class).
  - `work/scratch/` — logs, agent registry, throwaway (not committed).
- `scripts/` — spawn + messaging tooling (ported from the conductor repo).
  `config/` — worker settings + guard hooks.
- `research/` — per-subsystem findings (units, sprites, AI, netcode, …).
  The product of this repo. Evidence rule (hard rule 4) applies to every file.
- `tools/` — Python analysis scripts + Ghidra headless automation.
- `game/` — gitignored local install copy. Read-only (hard rule 2).

## Roles

- Spawned with a prompt naming a task file → you are a **worker**. The task
  file is your full contract — it starts with ZERO chat history. Follow it
  plus this rulebook.
- Otherwise → you are the **conductor**. The conductor DISPATCHES: cuts
  tasks, spawns workers, monitors, reviews, integrates. It does not write
  product code, tooling, or research itself — diagnosis it already holds
  goes INTO the task file, not into an editor. (Exception: maintaining this
  repo's own orchestration data and docs.)

## Task lifecycle

Status is DERIVED, never written. No `state:` line exists; nothing a worker
or conductor writes says "running" or "done". Precedence — the
furthest-along observable wins:

| status    | glyph | derived from                                          |
| --------- | ----- | ----------------------------------------------------- |
| completed | ✓     | `merged:` stamp in the task file (close-task.ps1 stamps it) |
| review    | ◎     | the task's PR is open                                 |
| blocked   | ⏸     | a worker question with no `re:` answer                |
| running   | ●     | a `work/scratch/agents/NNN.json` registry entry exists |
| queued    | ○     | none of the above — nobody has started                |

Workers write exactly three things, none a status: the `pr:` link, a report,
and questions. An unanswered question IS the blocked signal; answering it
clears it. Never hand-write `merged:` — close-task.ps1 stamps it.

Flow: cut → spawn → monitor (derived status + conductor inbox) → review
(MANDATORY GATE: no unreviewed change merges; check acceptance criteria
yourself, do not trust the worker's word) → merge → close.

### Never stop an agent without checking for an in-flight game (2026-08-09 incident)

`stop-agent.ps1` kills the agent's process tree. It does NOT kill a
StarCraft the agent launched — the game outlives its driver, keeps the
launch lock, and blocks EVERY other worker until someone notices.

This happened: task 024 messaged "ready for merge", started one last
regression run six seconds later, and the conductor stopped it mid-run.
The orphaned game held the machine for ~18 minutes while two workers
queued behind it, one of them prepared to wait 90.

Before `stop-agent.ps1`, ALWAYS:

1. `Get-Process StarCraft` **in the same breath as the kill, not minutes
   earlier**. A check from five minutes ago is worthless: the agent may have
   started a run in between — and if you have just told it to GO, that is
   exactly what it is doing. (2026-08-11: the conductor said GO, saw a stale
   heartbeat, and stopped the agent four minutes later. The agent had received
   the GO and launched at 11:04; the kill orphaned that game.)
2. "Ready for merge" does NOT mean "idle". A worker may start verification
   runs after reporting. Ask it to confirm it is idle, or merge first and
   stop it when it acknowledges.
3. **A stale heartbeat does not mean deaf.** It means the agent's turn ended —
   which is also what it looks like while a Monitor is armed and waiting. Before
   concluding an agent is unresponsive, send it something and give it time to
   answer; do not infer death from silence alone.
4. After stopping, re-check for a surviving game and for a
   `C:\sc-work\logs\sc-launch.lock` naming a dead pid.

Killing an orphan is allowed ONLY with positive proof it is orphaned — a
dead parent, a test output file that has stopped growing, and a lock file
naming a dead pid. Otherwise the standing rule holds: another worker's
game is another worker's run, and workers must never kill one themselves
(ask the conductor).

## Spawning workers

All commands run from `C:/git/decompile-sc` via the PowerShell tool (see
§ Messaging for why never Bash).

```powershell
# Cut a task + worktree + spawn in one command:
./scripts/new-task.ps1 -Slug <slug> [-Model sonnet] [-Title '...'] [-NoSpawn] [-Commit]
#   allocates next free NNN, fills work/tasks/_template.md into
#   work/tasks/NNN-<slug>.md (Goal/Context left as TODO(conductor) — fill them),
#   git fetch + worktree add C:/git/decompile-sc-taskNNN off origin/main.

# Spawn separately (after -NoSpawn):
./scripts/spawn-agent.ps1 -TaskFile work/tasks/NNN-<slug>.md -WorkDir C:/git/decompile-sc-taskNNN -Model <model>

# Merge — the ONE merge command, never `gh pr merge` by hand:
./scripts/merge-task.ps1 -Task NNN
#   refuses unless: caller is conductor, task has pr: and no merged:,
#   PR open, not behind origin/main, checks green. Squash-merges, then closes.

# Close a hand-merged PR (merge-task.ps1 calls this itself):
./scripts/close-task.ps1 -Task NNN [-StopAgent] [-Prune]
#   verifies PR is MERGED via gh (refuses otherwise), stamps merged:, commits
#   the task file + report. -Prune removes the clean worktree + branch.
```

- Conductor pre-creates the worktree and spawns the worker inside it
  (`-WorkDir`) — zero permission prompts. Default permissions: bypass.
- One task per worker. Parallel work → separate task files, one tab each.
- A finished no-PR task (research, `pr: -`) has nothing to merge — commit its
  task file + report directly after review.

## Messaging

Messages are files: `work/messages/<agent-id>/inbox/` (waiting) and
`read/` (processed). agent-id = task number for a worker (`003`),
`conductor`, or `user`. One message = one file with `from / to / sent /
subject` front matter.

- **PowerShell-not-Bash foot-gun**: run every `.ps1` via the PowerShell
  tool, NEVER the Bash tool. Bash invokes Windows PowerShell 5.1;
  `#Requires -Version 7` fails SILENTLY — nothing is written and the call
  looks sent. Always verify the script printed the written file path.
- NEVER delete or overwrite anything under `work/messages/` — real user
  messages live there. Reading files anywhere: fine.

```powershell
# Send:
./scripts/send-message.ps1 -To <agent-id> -From <agent-id> -Subject <s> (-Body <text> | -BodyFile <path>)

# Read + file in ONE atomic act (never cat + move later):
./scripts/read-message.ps1 -Agent <agent-id> [-All]

# Ask the human a decision — console renders one button per option:
./scripts/send-message.ps1 -To user -From NNN `
  -Subject 'Which Ghidra version?' -Body 'optional markdown context' `
  -Type question -Options '11.2; 10.4; no preference'
```

- `-Subject` IS the question; `-Options` is semicolon-separated, two or more.
- The answer arrives as a normal inbox message carrying `re: <question file>`.
  That `re:` line is what derives blocked/answered — the question file itself
  is never rewritten.
- Workers: arm a Monitor on your inbox at startup, send READY, re-arm after
  each message. A from-USER file in a worker inbox is informational — the
  conductor reviews and relays; workers act only on from-CONDUCTOR messages.
- Conductor: watch `work/messages/conductor/inbox/` while any worker runs;
  keep `work/messages/conductor/status.json` honest
  (`{"state","subject","updatedAt"}`).

## Model assignment

| model  | use for                                                        |
| ------ | -------------------------------------------------------------- |
| haiku  | trivial/mechanical: renames, file moves, format fixes          |
| sonnet | standard: well-specified tasks, investigations with clear steps |
| opus   | complex: multi-step judgement, gnarly debugging                |
| fable  | hardest: highest-ambiguity investigation, architecture         |

Record the choice in the task file (`model:` in Status).

## Conventions

- Worker worktrees: `C:/git/decompile-sc-taskNNN`, branch `taskNNN-<slug>`.
- Task ids: 3 digits, never reused, gaps never refilled. Slugs:
  lowercase-kebab (letters, digits, hyphens).
- Task heading: `# Task NNN — <title>` with an EM DASH (—, U+2014), spaces
  around it. Hard parser gate — a hyphen there makes the task INVISIBLE to
  the UI and to refresh-pr-status.ps1.
- Status block fields: `agent:`, `model:`, `pr:` only. No `state:` (status
  is derived), no hand-written `merged:` (close-task.ps1 stamps it).
- Reports: `work/reports/NNN-<slug>.md` unless the task reports via PR.
- PowerShell 7 only (`#Requires -Version 7` on every script); scripts run
  via the PowerShell tool, never Bash.
- Global rules in `~/.codex/AGENTS.md` apply to workers automatically.
