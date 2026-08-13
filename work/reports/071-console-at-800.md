# Task 071 — Move the console to the right edge at 800 wide

## Outcome

The task split into a shipped half and a measured NO-GO.

- **Shipped (wired into the (Wide) shortcut):** stage 3 widens the engine's
  input geometry from 640 to 800 in ten byte sites — the four window-proc mouse
  clamps and the mouse→world click search rect — so a click can REACH the new
  right quarter. Whether it SELECTS there is not provable off-screen and is the
  user's first-play test (same deferral 070 recorded for its item 1).
- **NO-GO:** moving the console into that region cannot be done by relocating
  dialog bounds — the bounds move the hit-test, not the on-screen pixels, which
  come from fixed-width console art (§15.5.3, black by the user's call). One
  follow-up, briefed by the picture and `research/renderer-viewport.md` §18.

## Shipped, measured (`test-widescreen-input-800.ps1`, logs under `C:\sc-work\logs\071\`)

| claim | result | oracle |
|---|---|---|
| stage 3 = 10 sites (8 clamps + 2 click-rect), ACTIVE 0 refused | yes | plugin install verdict |
| console unmoved (StatBtn 496-639), minimap at stock | yes | engine dialog list |
| 640 unchanged (flag off) + x<640 select works | yes | stock arm |
| x>639 SELECT | REPORTED no-select off-screen, not asserted | engine portrait |
| production-queue regression at stock | 0 failures | `test-production-queue.ps1` |
| local CI (incl. deploy stage-3 test) | 306 tests + hooktest PASS | `run-ci-local.ps1` |

## Two self-corrections (both caught before merge)

1. **The visual:** a prototype moved the dialog BOUNDS (engine list confirmed
   380-799 / 656-799) but the cnc-ddraw picture showed the console still at 640
   with a black right strip — the pixels come from fixed-width art, not the
   bounds. The dialog list is the right oracle for hit-test position, not a
   visual claim.
2. **The input:** an earlier run reported "click at x=672 selects" — contaminated
   (the Nexus was already selected). The clean deselect-first test read
   no-select, and THAT failure is what surfaced the second blocker (the 640-wide
   click search rect). A select-state read is only a select oracle if the target
   was provably deselected first.

Both are the frame-vs-memory / act-changes-the-read rules of tasks 023/026/033,
and both are in §18. The clean-slate oracle paid for itself: it found the
search-rect blocker the contaminated one would have hidden.

## The NO-GO, in the user's terms

Moving the console needs BOTH the pixels relocated (fixed-width art, no art for
640-799 — black by the user's call) AND the console click-router widened (a
stock router offers nothing at x≥640). Half a feature either way, so one
follow-up, and the move was dropped from what ships.

## Answered for 070

Its checklist item 1 has its concrete owner now (the 10 byte-patches); the
behavioural test is deferred to real play. 070's "128 px offset" was
nearest-unit-in-fixture under clamp-to-639. And the `console-800` capture is a
quiet fog-correctness datum: with one Nexus the map shrouds at the vision edge,
not at x=640.

## Deferred to the follow-up

The console move (pixels + click-router), briefed by §18 + the picture. The move
prototype, interact trace, and click probe are in this branch's pre-split git
history as that task's tools.
