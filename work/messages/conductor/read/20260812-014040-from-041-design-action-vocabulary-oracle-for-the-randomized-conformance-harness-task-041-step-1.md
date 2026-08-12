---
from: 041
to: conductor
sent: 2026-08-12T01:40:40Z
subject: DESIGN: action vocabulary + oracle for the randomized conformance harness (task 041 step 1)
---

Design of the randomized conformance harness, on paper, before any code — task 041 step 1.
Tell me if the ORACLE is wrong; that is the half worth arguing about.

## The shape

`tools/plugin/test-random-conformance.ps1`. ONE game launch, then N randomly
generated EPISODES inside it. The launch is the expensive part (~90 s); an episode is
10–25 s, so the episode count is the budget knob.

Every episode is: pick a random SUBSET of the fixture's buildings, select it a random
WAY, do a random number of things to it, then read the engine back. Selection size is
the axis that is randomised hardest, because that is the axis both of this week's bugs
lived on (037's upgrade mode, 038's two selection arrays).

## Action vocabulary

| action | random params | driven by |
|---|---|---|
| `select-box` | subset S, size 1..B | `Send-ScDrag` over the block's own map coords (WORLD scan) |
| `select-click` | one building | `Send-ScClick` |
| `group-assign` | group 1..9 | `Send-ScControlGroupAssign` |
| `group-recall` | group 1..9 | `Send-ScControlGroupRecall` |
| `train` | n presses, 1..12 | `Send-ScKey` on the card's Train hotkey |
| `cancel-last` | m presses | click the card's Cancel slot (0x20/0xFE) |
| `cancel-slot` | icon k of the status strip | `Get-ScStatusSlotPoint` |
| `drain` | wait for q items to finish | poll WORLD scan |
| `settle` | 0.5–3 s | sleep |

## The oracle — where each invariant's ground truth is READ

Every one of these is the engine's own memory or the engine's own funnel. The plugin's
counters appear once, as INV-P, and are labelled a self-check rather than an oracle.

| # | invariant | ground truth |
|---|---|---|
| INV-W | every Train press reaches the wire | `CMD id=0x1F` logged INSIDE the `queueCommand` (0x00485BD0) detour — the engine's own command funnel |
| INV-R | each selected building's ring <= 5 and holds only the trained type | that building's own `CUnit+0x98` / head `+0xA4`, dumped by PRODFAN for every SELECTED building (tracked or not) |
| INV-M | Δminerals == accepted × cost, charge AND refund | the engine's per-player resource globals (`minerals=`/`gas=` on PRODFAN/PRODQ) |
| INV-B | units that left the queue actually appear | the engine's per-player unit list, WORLD scan — count of the trained type owned by player 0 |
| INV-S | the building the plugin acts on is in the ENGINE's selection | `playersSelections` 0x006284E8 (`simSlots`) vs the client's `activePlayerSelection` 0x006284B8 (`clientCount`) — 038's exact seam |
| INV-U | upgrade levels rise by exactly the promoted count | the engine's level array 0x0058D2B0 / tech array 0x0058CF44 (`UPGQLVL`) |
| INV-H | the unit row was actually DRAWN | task 033's `ink` count over the control's own bounds in the dialog's 8-bit surface, with a known-drawn control as the positive control |
| INV-P | the plugin spent nothing of its own | `PRODQSTATS mineralsSpent=0` — SELF-CHECK, not an oracle |

INV-B is the user's own sentence ("verify it build 12 units and charged for 12"):
INV-M is the "charged for 12" half and INV-B is the "built 12" half, and both are read
from the engine.

## Fixture and the one trade-off in it

`-UnitBuildTime scv=6` (6 game seconds, task 031's knob). Default 20 s makes a drain
episode cost a minute per building; 1 s makes the ring drain DURING a press burst, and
then the ring never fills, the client never greys the button, and 038's bug cannot
reproduce at all. 6 s is above the longest burst (12 presses x 250 ms = 3 s) and below
anything that costs real time to drain. The burst step asserts `promoted==0` and
downgrades the exact-count assertions to inequalities if that ever fails, rather than
failing with nothing to say.

## Seed, and the round trip

The whole plan is a pure function of (seed, params) and is generated BEFORE the game
launches, written next to the log as JSON and printed. `-Seed N` reproduces it exactly;
`-Plan <file>` replays a plan verbatim. Every failure line carries the seed, the episode
index and the action index, and the run ends by printing the exact command line that
reproduces it.

## Budget

- gate run: one game, `-Episodes 6`, target <= 6 min wall clock. Measured and documented,
  not estimated.
- sweep: `-Episodes 40` (~25 min) or `-Games k` with derived seeds for an overnight run.

## Coverage, honestly

One game holds one player-owned building type, so the features split across three
profiles rather than pretending one fixture reaches them all:

- `production` (Command Centers) — sc_prodqueue, sc_prodfan, building control groups,
  cancel/refund, sc_queueind's data. THIS is the gate run.
- `upgrades` (Engineering Bay) — sc_upgrades, INV-U.
- `hudrow` (a 20-unit block) — sc_hudrow paging, INV-H.

The sweep runs all three; the gate runs `production` only. Anything a profile does NOT
cover is printed at the end of the run, so a green run cannot read as "everything was
exercised".

## Teeth test

038's fix is unmerged (PR #47), so current origin/main IS the parent. The generator run
against it should fail INV-W (5 of 9 presses reach the funnel, not 9) and INV-M
(charged 15 x 50, not 27 x 50) whenever an episode selects more than one building. Then
the same seed against #47's branch should pass. Both runs go in the PR.

Building it now; tell me if the oracle is wrong before I widen past the production profile.
