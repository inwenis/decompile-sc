# decompile-sc — rulebook

Full incident narratives live in `research/rulebook-history.md` (old headings preserved). Do NOT load it by default; follow a `->` pointer only when you need the evidence behind a rule.

## What this repo is

Personal, private reverse-engineering research on StarCraft; primary target the 1.16.1-era binary (richest public prior art: BWAPI offsets, community struct maps). Deliverables are DOCUMENTATION and TOOLING, never redistributed game content.
-> research/rulebook-history.md § "What this repo is"

## Hard rules

1. NEVER commit game binaries, MPQ archives, extracted assets, generated `.scm`/`.scx` fixtures, game frames/PNGs, or anything derived from them that reproduces game content. The repo tracks findings and tooling only; `.gitignore` is a backstop, not the rule.
   Frame writers throw on any in-repo path outside `work/scratch/`; put frames under `C:\sc-work\`.
   -> tools/plugin/drive-game.ps1; tools/plugin/run-with-plugin.ps1; tools/make-feature-test-map.ps1
2. `game/` (gitignored local install copy) is READ-ONLY. To patch a binary, copy it into your worktree or `work/scratch/` first.
3. NEVER point a modified binary at Battle.net or any online service. Offline and single-player only.
4. Every claimed address, offset or struct in `research/` carries how it was found AND how it was verified. No guessed offsets.
5. NEVER write live user state outside the repo and the working copy: registry, `%APPDATA%`, Documents, the desktop.
   `HKCU:\SOFTWARE\Blizzard Entertainment\*` holds the user's real game settings, and `New-Item -Force` on an existing key DELETES AND RECREATES it (22 settings wiped once).
   - DO prove any state-touching mechanism against a throwaway key or path first; prefer a process-scoped mechanism over persistent user state whenever both work.
   - The one exception: deployment targets the user chose (the deploy dir, a desktop shortcut). Write those, never destructively; `deploy.ps1` excludes player data (`characters\`, `save\`, `Maps\Replays\`, `maps\download\`, `SCScrnShot_*.pcx`).
   - The game's own UI writes the same key through the front door: see "Game Type" and "Tips dialog".
-> research/rulebook-history.md § "Project hard rules"; tools/deploy.ps1

## Before any suite run: arm `$env:AGENT_TASK`

- DO set `$env:AGENT_TASK` to a few digits (your PR or issue number, e.g. `$env:AGENT_TASK = '125'`) before ANY suite run, until orchestration is reinstalled.
  Why: nothing sets it since PR #121, and while it is empty `run-with-plugin.ps1` takes NO launch lock (`$takeLock`), does NO foreground hand-back (`$restoreForeground`), and `Resolve-ScFixtureDir` (drive-game.ps1) falls back to the forbidden shared `00-testmap` folder.
  The same digits become your fixture folder leaf, lock holder id, desktop tag and frame folder name.
  -> tools/plugin/run-with-plugin.ps1; tools/plugin/drive-game.ps1; tools/plugin/sc-launch-lock.ps1; tools/plugin/sc-desktop.ps1

## Running a suite

Suites run on an invisible Windows desktop; isolation costs nothing (75.0 s off-screen vs 75.2 s visible, same assertions).
- DO run `./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/test-<name>.ps1` by default, never the suite directly. `-Visible` is the debugging run.
- NEVER grow a separate watch mode and NEVER make suites or primitives desktop-aware. `-Visible` is the SAME code path (same child script, same CreateProcess, same args; only the desktop name differs).
  Why: a process inherits its desktop at creation and `EnumWindows` is desktop-scoped, so `Get-ScGameWindow`, `check-game-windows.ps1` and `close-game.ps1` follow the game untouched.
- `ClipCursor` is session-global, not desktop-scoped: a game on the invisible desktop pins the USER'S real mouse to a rectangle nobody sees. `run-offscreen.ps1` releases every clip it finds and prints the count; DO read that line, and NEVER add a second releaser inside a suite or the plugin.
  -> tools/plugin/run-offscreen.ps1 header ("THE CURSOR CLIP"); issue #135
-> research/rulebook-history.md § "A test run happens on an INVISIBLE DESKTOP"; tools/plugin/run-offscreen.ps1 header

## Launch lock

- DO NOT "improve away" `sc-launch-lock.ps1`: every launch is serialised by an exclusive OS file handle on `C:\sc-work\logs\sc-launch.lock`, acquired before anything touches the shared `ddraw.dll`.
  Why: StarCraft is single-instance PER MACHINE; invisible desktops fix visibility, not concurrency.
- Keep both gates that make the lock unreachable from the user's own play: `$env:AGENT_TASK`, and `-NoLaunchLock` baked into the deployed launcher.
- The handle is the lock; the file is diagnostic. `Exit-ScLaunchLock` removes the file and says so; a file naming a dead pid means a holder died without releasing (see "Stopping a run").
-> research/rulebook-history.md § "A test run happens on an INVISIBLE DESKTOP"; tools/plugin/sc-launch-lock.ps1 header

## Foreground

Three halves; reading one alone re-opens a real bug.
- Posted mouse moves, clicks and world drag-boxes do NOT need the foreground. NEVER raise the window for them; `Assert-ScWindowActive` refuses only a dead or MINIMISED window.
  NEVER "fix" a flaky input by activating the window: activation re-syncs the game cursor to the physical mouse (destroying the posted position) and `ClipCursor`s the user's real mouse to the game window.
  -> research/rulebook-history.md § "Foreground: only ONE primitive may raise"; drive-game.ps1 Set-/Assert-ScWindowActive docstrings; tools/plugin/probe-quiet-input.ps1
- `Send-ScDropdownPick` is the ONE primitive allowed to raise: a dropdown is press-and-hold, the game `SetCapture`s on button-down, and Windows grants capture only to the foreground. It raises for one pick and hands the foreground back.
  DO NOT delete it (the Game Type pick silently stops taking). DO NOT add a second raiser: a world drag-box is also a held button and needs none of this.
  -> research/rulebook-history.md § "Half 2: the dropdown, the one place a raise is allowed"; drive-game.ps1 Send-ScDropdownPick docstring
- The game raises itself at launch. `run-with-plugin.ps1` records the foreground right before `CreateProcess` and restores it once the game window exists (`sc-foreground.ps1`), with a second attempt after the health check. Leave it in place.
  Gated on `$env:AGENT_TASK`; `-NoForegroundRestore` (deployed launcher) and `$env:SCDRIVE_RAISE=1` each turn it off; off-screen it self-neutralises but still protects `-Visible` runs. The ~4 s residual hold is scinject's own settle, not fixable from here.
  -> research/rulebook-history.md § "Half 3: the LAUNCH borrows too, and gives it back"; tools/plugin/sc-foreground.ps1; tools/deploy.ps1
- `Set-ScWindowActive` is opt-in only: `-RaiseWindow`, or `$env:SCDRIVE_RAISE=1` for a human who wants to watch. NEVER set either from a suite.
- NEVER claim a run did not steal focus without `tools/plugin/watch-foreground.ps1` running beside it. A correct run shows one borrow-and-return pair for the launch (~6 s) plus one pair per Game Type pick; anything else is a bug.
- DO check every trace's StarCraft pid against the pid your launch printed. A different pid is ANOTHER StarCraft (the user's own play, or a competing launch bouncing off the single-instance check), not a fabricating tool.
  -> research/rulebook-history.md § "How to check a run did not steal focus"; tools/plugin/watch-foreground.ps1 header

## Glue-screen (menu) input under cnc-ddraw

Off-screen, the engine gates menu input on its activation state, and a window on an invisible desktop is never told it is active.
- DO set `$env:SCDRIVE_POST_ACTIVATE=1` for the menu walk: `drive-game.ps1` then posts `WM_ACTIVATEAPP(1)` + `WM_ACTIVATE(WA_ACTIVE)` + `WM_SETFOCUS` before EVERY posted input (the gate re-closes across screens) with a 500 ms settle (60 ms measured failing), and re-nudge-and-retry when the expected dialog does not appear.
  DO set it back to `0` once in game: the nudge re-syncs the cursor and is fatal before an in-game click.
- NEVER "fix" the off-screen click loss in `cnc-ddraw.ini` (`hook=1` and `noactivateapp=true` were both tried and reverted) and NEVER report it as the feature being broken. It is a harness limit.
- Any two-sample "did this region change" oracle calibrated under WMode is suspect under cnc-ddraw, which presents everything the engine draws (the selected browser row animates by itself). DO measure self-animating regions per batch as `Sync-ScBrowserToTop` does before trusting a settle.
-> research/rulebook-history.md § "Glue-screen input is ACTIVATION-GATED, and a shim decides whether the gate is open"; drive-game.ps1 Send-ScActivationNudge; research/renderer-viewport.md §17.2

## Game Type / `Custom Type`

`HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft\Custom Type` is ONE machine-wide value shared with the user's real play (its sibling `Recent Maps` holds their own campaign paths).
- DO read it, as `Set-ScGameType` does (out of the engine's dialog list, skipping the pick and the raise when it already matches). NEVER write it: the game's own UI performing a real pick is the only sanctioned writer.
  Expect the user's own games to change what suites need next, and a suite's pick to change the user's next default.
- A dropdown pick cannot succeed on the invisible desktop (`GetForegroundWindow()` reads 0 there all run). When a pick IS needed, the run must throw naming the desktop as the cause, never silently run a lesser test.
- When an off-screen run throws on the pick, DO run `./tools/plugin/prime-game-type.ps1` (launch, one pick against a stock map, read the combo back, quit without Start; under a minute, fixes the value for every suite) instead of re-running the failed suite `-Visible`.
  DO NOT guess a longer keyboard sequence instead; the foreground requirement for the pick stands until measured otherwise.
-> research/rulebook-history.md § "The game's own UI is a live-user-state WRITER too, not just this repo's code"; § "The one input that cannot work off-screen: a dropdown pick"; tools/plugin/prime-game-type.ps1 header

## Test fixtures

Your folder is `Maps\BroodWar\00-t<NNN>-<suite>\` (`<NNN>` = the digits in `$env:AGENT_TASK`), resolved by `Resolve-ScFixtureDir -Suite`.
- DO generate into your own per-run, per-suite folder; NEVER the shared `00-testmap`. Suites take `-FixtureDir` because the folder is the caller's choice; a multi-phase suite keeps the SAME folder across its own phases.
- DO name every fixture after its SUITE (`burrow-fanout.scx`), never the task, so "mine" is decidable from the filename alone; two suites generating `lurkers.scx` blocked a run outright.
- DO declare every fixture the run will create up front with `New-ScFixtureRun -Dir -Names`. Ownership is per-run, not per-file; anything outside the declared set is foreign, and refusing is still the answer.
- DO refuse to start if any `.scx` you did not declare is present, whether or not a game is running. Process liveness is NOT a sufficient test: playing someone else's map produces internally consistent nonsense.
- DO re-check the folder immediately before the browser walk, not only at generate time, and throw with the cause named rather than playing whatever is there.
- DO delete only your own declared files, on every path including `finally`. NEVER `Remove-Item -Recurse` a fixture folder.
- DO remove your folder at the end of the run, and only if it is empty; an empty folder of yours still pushes every browser entry below it down a row for everyone else.
- A wait or refusal message states only what the path proves (which run and suite own the folder, that a same-run-different-suite file is impossible, that no liveness check was performed). NEVER name a culprit without evidence.
- DO verify a generated fixture in the engine's memory, never in the generator's own read-back; a tool that verifies its own write with its own indexing verifies nothing (PTEx is player-major).
  -> research/rulebook-history.md § "Read a dialog's CONTENT from memory; never hash its pixels"; research/command-card.md §6.3; tools/make_test_map.py
-> research/rulebook-history.md § "Test fixtures: one folder per task, one NAME per suite"; § "Shared test-fixture folder"; drive-game.ps1 block comment above Resolve-ScFixtureDir

## Map browser

- NEVER click a map-browser row by number. `Select-ScBrowserMap` is the only thing that walks the browser: `Sync-ScBrowserToTop` first (the list opens already scrolled), every row computed from the filesystem, and the browser made to prove the clicked row was a map.
- `[Up One Level]` sorts alphabetically among folders, so ANY fixture folder moves it. "I don't use the shared folder" is not an exemption.
-> research/rulebook-history.md § "Never click a map-browser row by number"; drive-game.ps1 block comment above Get-ScBrowserListing

## Tips dialog

- DO dismiss the in-game tips dialog with `Dismiss-ScTipsDialog -Hwnd -LogPath` (waits for `Tips_Dlg` in the engine's active-dialog list, clicks the OK button's centre from its own bounds, throws if it is still up). NEVER a fixed point; a tips dialog left open eats every later click in the run.
- NEVER turn tips off through `HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft` (the dialog's own "Show Tips at Startup" checkbox writes that key). Dismiss for this run; leave the user's setting alone.
-> research/rulebook-history.md § "The in-game tips dialog is dismissed by ITS OWN button, never by a fixed point"; drive-game.ps1 Dismiss-ScTipsDialog docstring

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
- For any claim about what a dialog HOLDS (which button, which slot, enabled or greyed), DO walk the dialog and read its fields (`sc_card`/`sc_hudrow` show the shape; needs no hook, works in `-Mode observe`). Frame hashes and captures are corroboration for the human, never the oracle.
- DO take the read BEFORE the action as well as after, and make the verifier something other than the thing that acts (the Cloak slot flips to its Decloak face on success and reports "no Cloak button").
  -> research/rulebook-history.md § "Read a dialog's CONTENT from memory; never hash its pixels"; research/command-card.md §6.4
- A `ScLog` format string is an API: 24 `.ps1` files parse those lines, and a field inserted at the front of one silently stops every regex anchored to it. DO add a line you rely on to `tests/golden-line-seam.Tests.ps1`, which renders it from the C++ source and matches each suite's own regex against it.
  -> tests/golden-line-seam.Tests.ps1
- DO verify a UI action by reading the engine's own dialog list back afterwards, never by "no exception was thrown".
  -> tools/plugin/prime-game-type.ps1
- "The probe never ran" must never be indistinguishable from "nothing happened": a missing baseline or reference reads -1 (never 0), a skipped comparison counts what reached it, zero samples are not agreement, a null reading is not a clean result.
  DO use the named predicates in `tools/plugin/sc-oracle-guard.ps1` (`Test-ScReached`, `Test-ScWitnessed`, `Test-ScChanged`, `Test-ScExactRefund`, `Get-ScOverlap`) instead of inlining `-and $n -gt 0`; each has been watched failing in Pester.
  -> tools/plugin/sc-oracle-guard.ps1 header; tests/oracle-guard.Tests.ps1

## Oracles: pixel counts and instruments

**A count over a region the engine also paints saturates, and fails by looking HEALTHY.**
- DO measure a DIFFERENCE against a copy of the same rect taken on the GAME thread with our content absent (`ScQueueIndBoxDiff`, `indBoxDiff`). NEVER take that baseline on the frame the control hides on; take it again before a show that follows a hidden frame; report -1 (never 0) for a rect that has moved or has no baseline.
- A positive control (`refInk`) with no visible reference reports -1, and that is a FAILURE wherever a visible reference is required; NEVER fall back to a hidden control. A whole-surface count (`surfInk`) answers "is this probe blind" in every state.
- A difference asked the other way ("did we strand pixels") must carry the SIZE of what it looks for: `stranded=0` over an EMPTY glyph mask is a probe that never saw the line and must fail, not pass.
- Before asserting on any reading, DO vary the input and watch the number: two different inputs producing one identical count are a broken instrument, whatever the count is.
- When an instrument turns out to be blind, DO audit every other place it is load-bearing in the same sitting; one fixed call site is not a fixed instrument.
- DO decide that a surface has settled by wall clock, not call count (the status dispatcher runs tens of thousands of times a second, so "the next call" is the same painted frame). Print a call count only beside its own elapsed ms.
- For pixel comparisons DO assert on the SHAPE that separates damage from noise (a wrong pitch damages whole rows across the full width; animation differs in isolated blobs spanning no row) and report the noise floor beside the verdict, never assert against zero.
  -> research/rulebook-history.md § "An enumeration that scanned for a NAME is not exhaustive"; tools/plugin/analyze_present_frames.py
-> research/rulebook-history.md § "Assert the ENGINE'S OWN RESULT, not your bookkeeping"; tools/plugin/src/sc_queueind.cpp; tools/plugin/src/sc_hudrow.cpp; research/status-pane-text.md §5.2; research/hud-selection-row.md

## Oracles: threads, races, confounds

- A check that fails at random is worth as little as one that cannot fail: DO snapshot frame state on the game thread at end of frame, and keep the async walk only for memory the frame path never writes.
  -> research/rulebook-history.md § "Assert the ENGINE'S OWN RESULT, not your bookkeeping"; research/production-queue.md
- If the thing under test can go either way on identical input, one run is an anecdote: DO repeat it N times, print the rate AND N, and choose the swept axis for a stated reason (hold duration was the one variable that differed between harness and human).
- When a candidate fix perturbs the instrument, DO measure the defect with the fix reverted as well as applied; the raw defect can be deterministic where the fix made it noisy, and the deterministic arm is the one to reason from.
  -> research/rulebook-history.md § "A SINGLE SAMPLE OF A RACE IS NOT A RESULT — and neither is a rate whose denominator you did not pair"
- When the bug you are fixing sometimes works by accident, a green test proves nothing unless it also proves your fix made it green: DO count what the fix rescued (`pressKept`) and require that count to move across the click.
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

Hard rule 4 applies to every line of `research/`.
- When re-implementing an engine predicate, DO dump the engine function and take base, row and stride from its operands (`MOV EAX,[0x0051267C]` / `LEA EAX,[EAX+EAX*2]` / `MOV EAX,[ESI*4 + 0x006284E8]`). A global of the right shape and name next door agrees only while your tests are simple.
  -> research/rulebook-history.md § "Take the ADDRESS from the engine's own instructions, not from the global next door"; research/binary-selection-map.md §3.3-3.4; research/production-queue.md §10.2
- A verified reference count, byte pattern or value match proves EXISTENCE, not identity; only READING the referencing functions names what an address is. In any hand-off note, label the two strengths apart: "verified: N referencers; hypothesis: X".
- DO read the subsystem's research doc before trusting any inherited hypothesis about it (a hand-off note, a prior PR's claim).
  -> research/rulebook-history.md § "A verified enumeration of what TOUCHES an address says nothing about what the address IS"; research/renderer-viewport.md §16.1
- DO enumerate framebuffer writers by sweeping for the arithmetic SHAPE `k*pitch + d` (`tools/renderer_pitch_sweep.py`), never for the pointer or the pitch: a routine handed the pointer in a register never names it, and unrolled walks hold the pitch as displacements whose `+4` twins are multiples of nothing.
- A disassembly sweep must resume past undecodable bytes AND report the fraction of the section it actually covered; zero hits from partial coverage is indistinguishable from a correct all-clear.
  -> research/rulebook-history.md § "An enumeration that scanned for a NAME is not exhaustive"; research/renderer-viewport.md §12.4, §12.8

## Diagnostics and reporting

**Diagnostic lines are under the same rule as assertions: a wrong number in a log is worse than none, because you will reason from it.**
- A count you print must be a count something incremented: DO check every format specifier has an argument; a missing one prints stack garbage, not zero.
- DO count every exit term of a gate and print them together, so "it refused" names the test that refused and "holding nothing" is distinguishable from "was never handed anything" (`trainSeen`/`trainNoUnit` in `PRODQSTATS`).
- DO log function entry as well as outcome at least once, so "no log line appeared" is distinguishable from "the function returned false".
  -> research/rulebook-history.md § "Your DIAGNOSTICS are under the same rule as your assertions"; research/production-queue.md §10.4
- When a resource has two halves (a handle and a file, a process and its log, a registration and a directory), a success line must name the half it proves: print `released, removed <path>` or say exactly why the file stayed.
  -> research/rulebook-history.md § "A log line can be TRUE about the mechanism and FALSE about the state"; sc-launch-lock.ps1 Exit-ScLaunchLock
- A count and a count are not a correlation: to claim "the X that did A is the X that did B", every row must carry A and B together, or you are reading a coincidence of totals.
- DO quote a rate together with the run that produced it, never as a property of the system; the same sweep twenty minutes later moved.
  -> research/rulebook-history.md § "A SINGLE SAMPLE OF A RACE IS NOT A RESULT — and neither is a rate whose denominator you did not pair"
- DO state a measured negative at exactly the strength the evidence supports ("keyboard input did not reach the combo on the two paths tried"), never the stronger claim ("the combo provably ignores the keyboard"), or a probe that should run gets skipped on an overstated prior.
  -> research/rulebook-history.md § "The game's own UI is a live-user-state WRITER too, not just this repo's code"; tools/plugin/probe-gametype-keyboard.ps1

## Screenshots

**Hard rule 1 wins over the global "visual change -> screenshot -> pr-image" rule, always, without asking.**
- NEVER `pr-image` or commit a game frame. Prove visual claims with the in-process read-back oracles (`CIRCLES show:`, `HUDROW show n=... page=...`, `UNITSTATE`), describe the appearance in the PR body, and keep frames on the gitignored diagnostic path.
- User standing rule, verbatim: "when you tell me about ui elements you show me with screenshots - like `page i/j` - show me a screen shot of this. same with all other features you're telling me about - show me with screenshots"
- So every visual claim (PR body or message) carries a PNG of that exact state on disk under `C:\sc-work\logs\<NNN>-frames\` (via the suite's `-CaptureFrames` path where one exists), named for the STATE not a counter, before and after for anything claimed fixed, one pair per distinct case. The PATH travels, never the image.
- The read-back oracle stays the oracle: a frame is never asserted on, an oracle with no frame is not reportable, a frame with no oracle is not evidence.
-> research/rulebook-history.md § "Screenshots vs hard rule 1 (settled)"; tools/plugin/test-widescreen.ps1 (-CaptureFrames); tools/plugin/run-offscreen.ps1

## Stopping a run / orphaned games

**Killing a driver's process tree does NOT kill the StarCraft it launched.** The game outlives its driver, keeps the launch lock, and blocks every later launch until someone notices.
- Before killing any agent or test driver, DO run `Get-Process StarCraft` in the same breath as the kill, not minutes earlier. A run that has reported done may have started a verification run since; confirm it is idle first.
- After stopping anything, and after ANY driver death (including a harness kill at the launch step after scinject has handed the game off), DO re-check for a surviving game and for `C:\sc-work\logs\sc-launch.lock` naming a dead pid.
- A game is orphaned only when ALL THREE hold: the pid the launch printed is still running, the driver/suite process that launched it is gone, and that driver's own transcript has stopped advancing STEPS (`[7] click Train x12`).
  A dead parent is NOT evidence (the launcher exits once scinject hands off, so every harness game is parentless within seconds). A growing plugin log is NOT evidence (the plugin writes it, and the plugin is alive in an orphan by definition).
- DO kill an orphan only with that positive proof. A StarCraft you did not launch is another run's game or the user's own play: ask the user, NEVER kill it yourself.
-> research/rulebook-history.md § "Never stop an agent without checking for an in-flight game"; tools/plugin/close-game.ps1; tools/plugin/check-game-windows.ps1

## Plugin code reuse

- NEVER copy a helper into a second `tools/plugin/src` file or a second `tools/plugin/*.ps1` suite. Shared C++ goes in `sc_engine.h` (relocation, memory probe), `sc_unit.h` (CUnit and dialog reads), `sc_env.h` (`%SCPLUGIN_*%`), `sc_ledger.h` (per-building records) or `sc_log.h`; shared suite code goes in `sc-suite.ps1` (asserts, steps) or `drive-game.ps1` (game input).
- `python tools/check-reuse.py` is the gate and CI runs it over both; a copy that must stay goes in `tools/check-reuse.cpp.baseline` or `tools/check-reuse.ps1.baseline` with the reason in the PR that adds it.
- Copies drift silently: four copies of one memory probe had stopped agreeing about the low-end bounds check by the time anyone compared them.
-> tools/check-reuse.py (the block scan is jscpd through `npx`; needs Node on PATH)

## Layout

- `research/` per-subsystem findings: the product; hard rule 4 applies to every file.
- `tools/` the plugin, Python analysis, Ghidra headless automation, map + deploy tooling. `tests/` Pester tests for the tooling.
- `work/scratch/` gitignored throwaway; `work/defects/` defect patches for `tools/plugin/build-defect-arm.ps1`; `game/` gitignored read-only install copy.
-> research/rulebook-history.md § "Layout"

## Conventions

- PowerShell 7 only: `#Requires -Version 7` on every script; run scripts via the PowerShell tool, never Bash.
- The global rules in `~/.codex/AGENTS.md` apply here too.
- Worktrees under `C:/git/wt/decompile-sc/<branch>` are disposable and pruned after merge. NEVER let anything deployed or persistent point at a worktree path (the deployed launcher copies `run-with-plugin.ps1` + `check-game-windows.ps1` into the deploy tree for this reason).
  -> tools/deploy.ps1; tools/README-deploy.md
- `research/` docs cite the old rulebook as `AGENTS.md § "<heading>"` or "task NNN"; both resolve in `research/rulebook-history.md` (headings verbatim, archive line = old line + 15). NEVER reuse an old heading for different content. Code comments cite by topic instead (see "Comments").
-> research/rulebook-history.md § "Conventions"

## Comments

**A comment states a timeless WHY: it must read the same written today or in five years.**
- DO keep the why that only a comment can carry: invariants, engine facts, how an address was derived, a measured number that bounds a value, and a refuted approach as a prohibition with its evidence ("do not restore PRESSED here: 110,381 restores in one click, zero commands").
- NEVER narrate history in a comment: task ids, dates, PR/issue numbers, commit hashes, who changed what, "previously / originally / used to / no longer", refactor notes, tombstones for deleted code. That goes in the PR body, `git log`, or `research/<topic>.md` behind a one-line pointer.
- Budget: file header at most 15 lines, an inline block at most 8 unless every line is evidence a reader needs. One home per why, nearest the code it governs; a comment that restates its code is deleted, and a stale one is fixed or deleted, never left.
- DO cite a rule by TOPIC (`AGENTS.md § "Oracles: pixel counts and instruments"`), never by task id; PowerShell help keeps .SYNOPSIS/.PARAMETER/.EXAMPLE and trims .DESCRIPTION.
- CI runs `tools/check-comment-narration.py` (comment lines only). For a comment-only sweep, `tools/check-comment-only-diff.py <ref> <file>...` proves no code token moved.
-> tools/check-comment-narration.py header
## Adding a rule

- Format: imperative first (DO/NEVER), at most 3 lines; then at most ONE line of why; then a pointer (`-> research/rulebook-history.md § ` + the old heading in quotes, a `research/` doc, or a tool's block comment). No incident retelling, no tables.
- Budget: this file stays at or under 300 lines. To add, merge or cut. Re-read the whole section you touch and delete what you supersede.
- The narrative goes into the PR description and, if it carries evidence, a `research/` doc. NEVER append to `research/rulebook-history.md`; it is closed.
- Headings are searchable topic nouns: no dates, task ids or aphorisms in headings (an aphorism may be the bold first line under its topic).
