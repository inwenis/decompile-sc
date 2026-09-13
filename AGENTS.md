# decompile-sc — rulebook

Archived incident narratives live in `research/rulebook-history.md` (old headings preserved). Do NOT load it by default; follow a `->` pointer only when you need the evidence behind a rule.

## Working here
0. Done means proven end to end
1. Focus on the MVP for every feature
1. When you have a PR ready to merge - spawn a fresh subagent for a review
  1. verify each claim left by the review
  1. act on review finds that:
    1. simplifies code
    2. removes code
    3. updates outdates claims
  2. do not act on findings that:
    1. expose edge cases that we haven't observed in real life

## Hard rules

1. NEVER commit game binaries, MPQ archives, extracted assets, maps (stock or generated: a fixture is an edited copy of a Blizzard map), or anything else that reproduces game content; CI's extension ban is a backstop.
   Screenshots are allowed: whole game view, one per claim or state, never a frame dump or a crop that isolates a sprite, icon, portrait or UI panel. Write frames under `C:\decompile-sc-data\sc-work\` and copy in only the one you publish.
2. `C:\decompile-sc-data\sc-install` (the user's playable install) is READ-ONLY; `run-with-plugin.ps1`, `scinject.exe` and `deploy.ps1` refuse it. Patching is in-process only: `StarCraft.exe` in the working copy `C:\decompile-sc-data\sc-work\1161-base` stays byte-identical to pristine; to patch a binary on disk, copy it into `work/scratch/` first.
3. Offline and single-player only: NEVER open Multiplayer (Battle.net, any gateway, LAN); menu walks click Single Player only.
4. Every claimed address, offset or struct in `research/` carries how it was found AND how it was verified. No guessed offsets.
5. NEVER write live user state outside the repo and the working copy: registry, `%APPDATA%`, Documents, the desktop.
   - Exception: the game's own settings, `HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft`, when that makes development simpler: `./tools/sc-registry-baseline.ps1 -Save` right before you write, `-Restore` when done. One standing write: `run-with-plugin.ps1` sets `Custom Type` before every agent launch and leaves it set (see "Game Type"). NEVER touch its sibling keys: they hold the Battle.net app's login.
   - DO prove any state-touching mechanism against a throwaway key or path first; prefer a process-scoped mechanism over persistent user state whenever both work.
   - Deployment targets the user chose (the deploy dir, a desktop shortcut) are written too, never destructively (`deploy.ps1` excludes and tripwires player data).
-> research/rulebook-history.md § "Project hard rules"; tools/deploy.ps1

## Before any suite run: arm `$env:AGENT_TASK`

`run-offscreen.ps1` refuses to start without it (your PR or issue digits, e.g. `$env:AGENT_TASK = '125'`).

## Running a suite

- DO run `./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/test-<name>.ps1` by default, never the suite directly. `-Visible` is the debugging run.
- NEVER make a suite or primitive behave differently off-screen: one that silently does less there is a false green. `-Visible` is the same code path, so debug with it.
- `ClipCursor` is session-global, not desktop-scoped: a game on the invisible desktop pins the USER'S real mouse. `run-offscreen.ps1` releases every clip it finds (sparing one inside the user's own visible StarCraft window) and prints the count; DO read that line, and NEVER add a second releaser inside a suite or the plugin.
  -> tools/plugin/run-offscreen.ps1 clip-watch loop; issue #135
-> research/rulebook-history.md § "A test run happens on an INVISIBLE DESKTOP"; tools/plugin/run-offscreen.ps1 header

## Launch lock

- NEVER bypass, weaken or reorder `sc-launch-lock.ps1` (taken before anything touches the shared `ddraw.dll`): StarCraft is single-instance per machine, whatever the desktop. Its header explains the handle and a leftover lock file.
- Keep the lock agents-only on BOTH guards: the `$env:AGENT_TASK` term in `run-with-plugin.ps1` and the deployed launcher's `-NoLaunchLock`.

## Foreground

Posted moves, clicks, drags and keys need no foreground; only the launch borrows it, and `run-with-plugin.ps1` hands it back.
- NEVER raise or activate the game window to deliver input or to fix a flaky one: activation re-syncs the game cursor to the physical mouse and `ClipCursor`s the user's mouse. Off-screen a raise cannot succeed; on a `-Visible` run nothing stops it.
- NEVER set `$env:SCDRIVE_RAISE=1` or call `Set-ScWindowActive` from a suite or probe: they are for a human watching, and `SCDRIVE_RAISE` also switches off the launch hand-back.
- Leave `run-with-plugin.ps1`'s launch foreground hand-back in place: off-screen it only logs 'no foreground window to record', but it protects `-Visible` runs.
- NEVER claim a run did not steal focus without `tools/plugin/watch-foreground.ps1` running beside it. A correct off-screen run shows no game foreground; a correct `-Visible` run shows one borrow-and-return pair for the launch (~4 s); anything else is a bug.
- DO check every trace's StarCraft pid against the pid your launch printed. A different pid is ANOTHER StarCraft (the user's own play, or a competing launch bouncing off the single-instance check), not a fabricating tool.
  -> research/rulebook-history.md § "How to check a run did not steal focus"; tools/plugin/watch-foreground.ps1 header
-> research/rulebook-history.md § "Foreground: only ONE primitive may raise"; drive-game.ps1 Set-/Assert-ScWindowActive docstrings; tools/plugin/sc-foreground.ps1

## Glue-screen (menu) input under cnc-ddraw

Off-screen, cnc-ddraw menu input is activation-gated: a harness limit, not a feature bug (ini fixes were tried; see the `cnc-ddraw.ini` header). Walk menus with `Enter-ScCustomGame -ActivationNudge` (drive-game.ps1), which sets and clears `$env:SCDRIVE_POST_ACTIVATE`; why: `Send-ScActivationNudge` docstring.
- DO keep `$env:SCDRIVE_POST_ACTIVATE` at `0` once in game (`Enter-ScCustomGame`'s `finally` does): the nudge re-syncs the cursor and every playfield click-select then comes back empty.
- Any two-sample "did this region change" oracle calibrated under WMode is suspect under cnc-ddraw, which presents everything the engine draws (the selected browser row animates by itself). DO measure self-animating regions per batch as `Sync-ScBrowserToTop` does before trusting a settle.
-> research/rulebook-history.md § "Glue-screen input is ACTIVATION-GATED, and a shim decides whether the gate is open"; research/renderer-viewport.md §17.2

## Game Type / `Custom Type`

`run-with-plugin.ps1` writes `Use Map Settings` into `Custom Type` (HKCU, machine-wide, shared with the user's play) before every agent launch and leaves it set; `Assert-ScGameType` reads it back from the engine's dialog list.
- NEVER add a dropdown pick: it needs the foreground, which an off-screen run never has. NEVER catch `Assert-ScGameType`'s throw and pass a lesser test.
-> research/ability-semantics.md §8.1

## Test fixtures

Fixture ownership is code: copy `test-burrow-fanout.ps1`'s recipe (`Resolve-ScFixtureDir -Suite`, `New-ScFixtureRun` declaring every file, named after the suite, `Wait-ScFixtureFolderFree`, `Assert-ScFixtureStillMine` right before `Select-ScBrowserMap`, `Remove-ScOwnFixture` + `Remove-ScOwnFixtureDir` in `finally`).
- DO default `-FixtureDir` with `Resolve-ScFixtureDir -Suite <suite>`; a hardcoded folder is shared by every task running that suite.
- NEVER run one suite twice at once under one `$env:AGENT_TASK` without distinct `-FixtureDir`s: same folder, same names, and the second run's `Wait-ScFixtureFolderFree` silently deletes the first run's map.
- NEVER delete or skip an undeclared `.scx` because no StarCraft is running: its owner may not have launched yet.
- NEVER `Remove-Item -Recurse` a fixture folder (in a suite, a helper, or by hand, even when `Get-ScBrowserEntry` says to clear stale folders): another task's game may be reading it.
-> research/rulebook-history.md § "Test fixtures: one folder per task, one NAME per suite"; drive-game.ps1 block comment above Resolve-ScFixtureDir

## Map browser

- NEVER click a map-browser row by number; pick maps only with `Select-ScBrowserMap` (why: drive-game.ps1 block comment above Get-ScBrowserListing).

## Tips dialog

- DO dismiss the in-game tips dialog with `Dismiss-ScTipsDialog -Hwnd -LogPath`, never a fixed point: a tips dialog left open eats every later click in the run.

## Command card clicks

- In any loop that clicks a card button more than once, DO re-read the card before each click and stop the moment the condition that put the button there is gone. Taking the button by ACTION rather than slot is necessary, not sufficient: the action is what changes (Terran slot 9 is Cancel while training, Lift Off when idle).
- DO end every multi-click card sequence by asserting the status pane still holds the unit you were measuring (`portrait type`); a lift-off, a lost selection and a click on terrain all produce consistent readings about the wrong unit.
-> research/rulebook-history.md § "A CARD SLOT CHANGES MEANING UNDER YOU — re-read it before every click"; research/production-queue.md §8.3

## Oracles: what counts as a read-back

**A check that cannot fail is worth nothing; so is one that fails at random.**
- For any feature that begins with player input (click, hotkey, card button), DO watch the engine's command funnel `queueCommand` 0x00485BD0 in a REAL game before trusting your handler. Offline tests prove your code does what you meant; only the wire proves the game asks it to.
  -> research/rulebook-history.md § "A player-input feature is unproven until the wire has been watched"; research/production-queue.md
- DO assert the thing the ENGINE changed (its arrays, unit fields, resource globals, dialog fields), never merely that your own structure holds the right number of items.
- When the plugin evaluates an engine predicate on the engine's behalf, DO evaluate it in the state the action will ACTUALLY run in (level N+1's requirement block; the simulation's selection, not the client's): project forward when that state does not exist yet, re-read right before acting when it does.
- A read-back of your own buffer is not a read-back. "Was it drawn" reads what the engine left behind (the dialog's own 8-bit surface inside the control's bounds); the engine's string draw silently refuses when `top + fontHeight > clip.bottom`.
  -> research/rulebook-history.md § "Assert the ENGINE'S OWN RESULT, not your bookkeeping"; research/hud-selection-row.md; research/production-queue.md §10.2
- For any claim about what a dialog HOLDS (which button, which slot, enabled or greyed), DO walk the dialog and read its fields (`sc_card` shows the shape; its walk needs no hook and works in `-Mode observe`). Frame hashes and captures are corroboration for the human, never the oracle.
- DO take the read BEFORE the action as well as after, and make the verifier something other than the thing that acts (the Cloak slot flips to its Decloak face on success and reports "no Cloak button").
  -> research/rulebook-history.md § "Read a dialog's CONTENT from memory; never hash its pixels"; research/command-card.md §6.4
- A `ScLog` line a suite parses is an API: a field inserted ahead of a parsed one silently zeroes the parser. DO register each parser (suite + regex) in `tests/golden-line-seam.Tests.ps1`; CI catches drift only for registered ones.
- DO verify a UI action by reading the engine's own dialog list back afterwards, never by "no exception was thrown".
- "The probe never ran" must never read as "nothing happened": a missing baseline or reference reads -1 (never 0), a skipped comparison counts what reached it, zero samples or a null reading is not a pass.
  DO use the predicates in `tools/plugin/sc-oracle-guard.ps1` instead of inlining `-and $n -gt 0`.

## Oracles: pixel counts and instruments

**A count over a region the engine also paints saturates, and fails by looking HEALTHY.**
- DO measure a DIFFERENCE against a copy of the same rect taken on the GAME thread with our content absent, reporting -1 (never 0) when no valid copy exists; when that copy may be taken is stated at `ScQueueIndBoxDiff` (sc_queueind.h) and `IndicatorFrame`/`BandDiff` (sc_hudrow.cpp).
- Before asserting on any reading, DO vary the input and watch the number: two different inputs producing one identical count are a broken instrument, whatever the count is.
- When an instrument turns out to be blind, DO audit every other place it is load-bearing in the same sitting; one fixed call site is not a fixed instrument.
- DO decide that a surface has settled by wall clock, not call count (the status dispatcher runs tens of thousands of times a second, so "the next call" is the same painted frame). Print a call count only beside its own elapsed ms.
- Frame comparisons go through `frame-diff.py` (or `frame-capture.py diff`): assert on `wide_rows` (shape), never on a zero diff, and print the noise floor beside the verdict; the header says why.
-> research/rulebook-history.md § "Assert the ENGINE'S OWN RESULT, not your bookkeeping"; tools/plugin/src/sc_queueind.cpp; tools/plugin/src/sc_hudrow.cpp; research/status-pane-text.md §5.2; research/hud-selection-row.md

## Oracles: threads, races, confounds

- A check that fails at random is worth as little as one that cannot fail: DO snapshot frame state on the game thread at end of frame, and keep the async walk only for memory the frame path never writes.
  -> research/rulebook-history.md § "Assert the ENGINE'S OWN RESULT, not your bookkeeping"; research/production-queue.md
- If the thing under test can go either way on identical input, one run is an anecdote: DO repeat it N times, print the rate AND N, and choose the swept axis for a stated reason (hold duration was the one variable that differed between harness and human).
- When a candidate fix perturbs the instrument, DO measure the defect with the fix reverted as well as applied; the raw defect can be deterministic where the fix made it noisy, and the deterministic arm is the one to reason from.
  -> research/rulebook-history.md § "A SINGLE SAMPLE OF A RACE IS NOT A RESULT — and neither is a rate whose denominator you did not pair"
- When the bug you are fixing sometimes works by accident, a green test proves nothing unless it also proves your fix made it green: DO require the fix's own activity counter to move across the action (`phantom`) and its tripwire to stay still (`disableOnOwned` +0).
  -> research/production-queue.md §8.8; tools/plugin/test-production-queue.ps1
- A confound correlated with the treatment arm and pointing at the conclusion must be designed out, not tolerated: DO fix the fixture so it cannot happen AND gate the run so a measurement window in which it happened cannot be published.
  -> research/rulebook-history.md § "Read a dialog's CONTENT from memory; never hash its pixels"; tools/plugin/probe-queue-indicator-frames.ps1

## Oracles: absence and defect-era checks

- DO prove an absence pattern matches a log where the thing DID happen before requiring it absent, and pair every absence check with a positive one in the same run ("the ability fired in this arm" beside "nothing was interrupted").
  -> research/rulebook-history.md § "Absence assertions must first be proved positive"; sc-oracle-guard.ps1 Get-ScOverlap; research/ability-semantics.md §8.5
- Writing an oracle while a known defect is live: DO ask what the assertion reads on a CORRECT build, not only today. If you cannot say, assert only the defect-independent part and REPORT the rest.
- On a red right after fixing a bug: DO date the check before touching fix or check. If it was calibrated while the bug was live, re-derive the expectation from the MECHANISM and cite the pre-fix and post-fix readings beside it. Register the predicted reading before the run so the red is legible as confirmation, not regression.
  -> research/rulebook-history.md § "An oracle written during a defect era can encode the defect as its expectation"; research/renderer-viewport.md §16.4

## Generated suites (random, fuzzed, property-based)

- DO name the ONE seam the suite exists to reach, count the episodes that actually reached it, and print that count beside the verdict every run; when it is zero, print which class of bug the run cannot detect. "How many cases were generated" is not that number.
- A verdict must depend on reaching the end of the work: DO record that the episode loop finished, print `INCOMPLETE` (its own word, never `PASS`) with the episode count otherwise, and catch exceptions as recorded failures; `| Tee-Object` swallows the non-zero exit.
- DO choose the seed because its plan reaches the seam (checked in the offline plan generator, no game involved) and say so in the PR; a seed chosen because it produced the desired result is seed-shopping. An unseeded run still prints the seed it chose.
-> research/rulebook-history.md § "A random suite must report the coverage of its SEAM, not only its verdict"; tools/plugin/conformance-verdict.ps1; tools/plugin/test-random-conformance.ps1

## Engine-owned flags

**A flag you rewrite every frame is a flag the engine re-asserts every frame, and its re-assertion is an EVENT.**
- Before writing any engine-owned flag on a repeating path, DO find the engine's own writer and read it as a FUNCTION: what it does besides the store (events sent, handlers called, redraws queued) and whether it early-outs when the bit already has its value. Your rewrite turns its no-op into a live call every frame.
- Treat a "times I wrote this field" counter in the hundreds of thousands per run as a fight with the engine's writer, not the feature working hard; whatever that writer does on the way now happens at that rate too.
- State that lives between two user events (a press, a capture, a hover, a drag origin) is destroyed by a mid-gesture re-layout and invisible to every frame-boundary read-back. DO verify input paths by tracing the gesture, never by concluding "clickable" from end-of-frame state.
- When one control misbehaves, DO instrument the WORKING control beside it in the same run, same frame, same dialog, so the failing trace has a baseline that makes it legible as abnormal.
-> research/rulebook-history.md § "A FLAG YOU REWRITE EVERY FRAME IS A FLAG THE ENGINE RE-ASSERTS EVERY FRAME — and re-assertion is an EVENT"; research/production-queue.md §8.6; research/command-card.md

## Claims about the binary

- When re-implementing an engine predicate, DO dump the engine function and take base, row and stride from its operands (`MOV EAX,[0x0051267C]` / `LEA EAX,[EAX+EAX*2]` / `MOV EAX,[ESI*4 + 0x006284E8]`). A global of the right shape and name next door agrees only while your tests are simple.
  -> research/rulebook-history.md § "Take the ADDRESS from the engine's own instructions, not from the global next door"; research/binary-selection-map.md §3.3-3.4; research/production-queue.md §10.2
- A verified reference count, byte pattern or value match proves EXISTENCE, not identity; only READING the referencing functions names what an address is. In any hand-off note, label the two strengths apart: "verified: N referencers; hypothesis: X".
- DO read the subsystem's research doc before trusting any inherited hypothesis about it (a hand-off note, a prior PR's claim).
  -> research/rulebook-history.md § "A verified enumeration of what TOUCHES an address says nothing about what the address IS"; research/renderer-viewport.md §16.1
- DO enumerate framebuffer writers with `tools/renderer_pitch_sweep.py` (the `k*pitch + d` shape), never by searching for the pointer or the pitch; its docstring says why.
- A disassembly sweep must resume past undecodable bytes AND report the fraction of the section it actually covered; zero hits from partial coverage is indistinguishable from a correct all-clear.
  -> research/rulebook-history.md § "An enumeration that scanned for a NAME is not exhaustive"; research/renderer-viewport.md §12.4, §12.8

## Decompiled C

- DO read a function as C before its asm: `C:\decompile-sc-data\sc-work\decomp\StarCraft.exe\0x<ENTRY>.<name>.c`, one file per function, `listing.asm` beside it; `ranges.tsv` maps a code address to its function, `types.txt` a struct offset to its field, a grep for `\bname\b` also hits stubs that jump into a shared tail and misses table/register calls (real call sites: `call   0x<addr>` in `listing.asm`). Missing? `./tools/ghidra/decomp-all.ps1`.
  A name with `nameSource` IMPORTED is a Magnetar hypothesis, USER_DEFINED this repo's (`tools/ghidra/magnetar-overrides.tsv`): hard rule 4 applies before either enters `research/`, and where they disagree the cited evidence decides, not the side.
  Why: a static asm read of the terrain blitter was "clean" and wrong; in C its run+1 defect is one loop condition.
  -> tools/ghidra/README.md § "Whole-binary decompile with names"

## Diagnostics and reporting

**Diagnostic lines are under the same rule as assertions: a wrong number in a log is worse than none, because you will reason from it.**
- A count you print must be a count something incremented, never a constant (the build's `-Wall -Werror` rejects a missing format argument everywhere except `DlgAppend`).
- DO count every exit term of a gate and print them together, so "it refused" names the test that refused and "holding nothing" is distinguishable from "was never handed anything" (`trainSeen`/`trainNoUnit` in `PRODQSTATS`).
- DO log function entry as well as outcome at least once, so "no log line appeared" is distinguishable from "the function returned false".
  -> research/rulebook-history.md § "Your DIAGNOSTICS are under the same rule as your assertions"; research/production-queue.md §10.4
- When a resource has two halves (a handle and a file, a process and its log, a registration and a directory), a success line must name the half it proves, or say exactly why the other half stayed.
  -> research/rulebook-history.md § "A log line can be TRUE about the mechanism and FALSE about the state"
- A count and a count are not a correlation: to claim "the X that did A is the X that did B", every row must carry A and B together, or you are reading a coincidence of totals.
- DO quote a rate together with the run that produced it, never as a property of the system; the same sweep twenty minutes later moved.
  -> research/rulebook-history.md § "A SINGLE SAMPLE OF A RACE IS NOT A RESULT — and neither is a rate whose denominator you did not pair"
- DO state a measured negative at exactly the strength the evidence supports ("keyboard input did not reach the combo on the two paths tried"), never the stronger claim ("the combo provably ignores the keyboard"), or a probe that should run gets skipped on an overstated prior.
  -> research/rulebook-history.md § "The game's own UI is a live-user-state WRITER too, not just this repo's code"

## Screenshots

- User standing rule, verbatim: "when you tell me about ui elements you show me with screenshots - like `page i/j` - show me a screen shot of this. same with all other features you're telling me about - show me with screenshots"
- So every visual claim (PR body or message) carries a PNG of that exact state (the suite's `-CaptureFrames` path where one exists), named for the STATE not a counter, before and after for anything claimed fixed; in a PR, embed it with `pr-image` within hard rule 1's limits.
- The read-back oracle stays the oracle (`CIRCLES show:`, `HUDROW show n=... page=...`, `UNITSTATE`): a frame is never asserted on, an oracle with no frame is not reportable, a frame with no oracle is not evidence.
-> tools/plugin/test-widescreen.ps1 (-CaptureFrames)

## Stopping a run / orphaned games

**Killing a driver's process tree does NOT kill the StarCraft it launched.** The game outlives its driver and, StarCraft being single-instance, blocks every later launch until someone notices.
- Before killing a test driver, DO run `Get-Process StarCraft` in the same breath as the kill, not minutes earlier. A run that has reported done may have started a verification run since; confirm it is idle first.
- After stopping anything, and after ANY driver death (including a harness kill at the launch step after scinject has handed the game off), DO re-check for a surviving game.
- A game is orphaned only when ALL THREE hold: the pid the launch printed is still running, the driver/suite process that launched it is gone, and that driver's own transcript has stopped advancing STEPS (`[7] click Train x12`).
  A dead parent is NOT evidence (the launcher exits once scinject hands off, so every harness game is parentless within seconds). A growing plugin log is NOT evidence (the plugin writes it, and the plugin is alive in an orphan by definition).
- DO kill an orphan only with that positive proof. A StarCraft you did not launch is another run's game or the user's own play: ask the user, NEVER kill it yourself.
-> research/rulebook-history.md § "Never stop an agent without checking for an in-flight game"; tools/plugin/close-game.ps1; tools/plugin/check-game-windows.ps1

## Plugin code reuse

- NEVER copy a helper into a second `tools/plugin/src` file or `tools/plugin/*.ps1` suite, even one the reuse gate misses (a short or renamed copy). Shared homes: `sc_engine.h`, `sc_unit.h`, `sc_env.h`, `sc_ledger.h`, `sc_log.h`; `sc-suite.ps1`, `drive-game.ps1`.
- Gate: `python tools/check-reuse.py` (CI); its failure message says how to baseline a deliberate copy.

## Conventions

- PowerShell 7 (`#Requires -Version 7` on every entry script) except `play.ps1`, which must stay Windows PowerShell 5.1 (the README one-liner runs it under `powershell`); run scripts via the PowerShell tool, never Bash.
- NEVER point anything persistent (launcher, shortcut, scheduled task, env var) at a `C:/git/wt/...` path: worktrees are disposable and pruned after merge.
- NEVER name a new AGENTS.md heading after a `research/rulebook-history.md` heading unless it carries that same rule: old `AGENTS.md § "..."` citations resolve there.

## Comments

**A comment states a timeless WHY: it must read the same written today or in five years.**
- Default to no comments
- DO keep the why that only a comment can carry: invariants, engine facts, how an address was derived, a measured number that bounds a value, and a refuted approach as a prohibition with its evidence ("do not restore PRESSED here: 110,381 restores in one click, zero commands").
- NEVER narrate history in a comment or docstring: beyond what CI's `tools/check-comment-narration.py` catches, that means no commit hashes, bare `#N`, non-ISO dates, who changed what, refactor notes or tombstones; history goes in the PR body, `git log` or `research/<topic>.md`.
- Budget: file header at most 15 lines, an inline block at most 8 unless every line is evidence a reader needs. One home per why, nearest the code it governs; a comment that restates its code is deleted, and a stale one is fixed or deleted, never left.
- DO cite a rule by its current AGENTS.md heading (`AGENTS.md § "Oracles: pixel counts and instruments"`); PowerShell help keeps .SYNOPSIS/.PARAMETER/.EXAMPLE and trims .DESCRIPTION.
- For a comment-only sweep, `tools/check-comment-only-diff.py <ref> <file>...` proves no code token moved.

## Adding a rule

- Format: imperative first (DO/NEVER), at most 3 lines, at most ONE line of why, then a `->` pointer; no incident retelling, no tables (the narrative goes in the PR).
- A rule a check enforces (CI, a Pester test, a throw before the harm) gets at most a one-line notice naming the check; prefer turning a rule into such a check over writing it here.
- To add, merge or cut (a test caps this file at 300 lines): re-read the whole section you touch and delete what you supersede.
- Headings are searchable topic nouns, never aphorisms or PR/issue ids (an aphorism may be the bold first line under its topic). Code cites headings as `AGENTS.md § "..."` and nothing checks them: grep before renaming or removing one.
