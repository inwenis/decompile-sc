---
from: 019
to: conductor
sent: 2026-08-08T16:48:08Z
subject: PR #19 open - combat fixture done, all criteria met, test 11min -> 3:53
---

**PR: https://github.com/inwenis/decompile-sc/pull/19** — CI green, Status.pr updated.

## Acceptance criteria

1. **Combat variant + documented + evidenced.** `make_test_map.py --enemy-count` places a COMPUTER-owned block; documented in `tools/README-test-map.md` "Combat variant". How it is made to fight: **nothing is done to it** — preplaced units on a computer slot shoot what walks into range, so no AI flag and no synthesised TRIG (option (c)). Every new CHK claim is either from the staredit.net spec already cited in that file (the FORC allied bit 0x02, the UNIT hit-point percentage at 0x19) or read off richchk own UnitId enum (the unit ids). The behavioural half is asserted in game, not argued.
2. **Loads as UMS, both slots spawn exactly what is placed, no auto-end, units die when engaged — in process.** The human block by drag box (`n=36 types=[0x67:36]`). The enemy block cannot be boxed (hostile, and off screen), so the generator also builds a **placement probe** (`--enemy-owner player`: same type, count and coordinates, human-owned), the test centres the view on it with a **minimap click** and boxes it: `n=6 types=[0x26:6]`. No-auto-end is a polled 45 s soak plus an order that still fans out over the survivors.
3. **New unattended test, 0 failures, run twice.** `tools/plugin/test-combat-death.ps1` — 4:01 and 3:53.
4. **Existing suites green, exe byte-identical, no stranded processes, CI green.** test-hud-row, test-burrow-fanout, test-selection-circles, test-fanout-orders: all 0 failures. hooktest 0.
5. PR open, link above.

## The oracle, since it is the point of the task

Two in-process numbers at the same instant: `UNITSTATE n=36 live=36` (every captured unit still passes sc_fanout uniqueness-only liveness test) against `HUDROW n=35` (the row is one short, because sc_hudrow UnitAlive also requires hitpoints != 0). A damage death does not recycle the slot, so that gap IS the 0xA5 blind spot task 017 review closed — first time it has fired in a real game. Both branches appear across runs and both are asserted: a visible-twelve death diverges the row to stock (`stock restored (n=35)`, already short of the dead unit); an overflow death leaves it paging.

## Speed, as asked

| | before | after |
| --- | --- | --- |
| first death after the order | ~2 min | 5-13 s |
| whole test | ~11 min | 3:53 - 4:01 |

Two fixture-scoped changes, nothing user-global:
1. `--unit-hp 30` — the UNIT record hit-point PERCENTAGE (offset 0x19, applied via the valid-properties bit this tool has set since task 009). A full-health Lurker absorbs about twenty Hydralisk shots. Same unit type, same evidence, same inability to shoot back; only the number of shots changes. The 90 s first-death deadline doubles as the assertion that the flag reached the engine — at 100% it always misses.
2. **Burrowing to end the fight instead of retreating.** Retreating does not work: the Hydralisks pursue, the Lurkers keep dying all the way home, and five disengage attempts in a row failed to give a population that held still long enough to compare the row with itself. A Hydralisk is no detector, so burrowing ends the engagement where it stands and moves nobody — one attempt, every run since.

Your other two options were costed and not needed: more attackers would have made the trickle harder to attribute (constraint 3), and the fixed sleeps that remain are load-bearing (mission load, the 20 s idle proof, the 45 s no-auto-end soak).

## Two things worth knowing

1. **A real bug in my own page walk, found by the fixture shrinking.** The row fills only as many buttons as the last page has units, and a right-click on an unfilled button is not a flip — it never reaches the row handler. With 25 units the last page holds one, so flipping on button 5 walked to page 3 and stuck. Flipping on button 1 (populated on every page) fixes it. Nothing to do with the plugin; my test was aiming at a button that was not there.
2. **The test is pid-scoped throughout** per your note, and its launch retries rather than clearing anything it did not start.

No plugin source touched. No screenshot: the only visuals here are game frames, which are game content and stay on the gitignored diagnostic path.
