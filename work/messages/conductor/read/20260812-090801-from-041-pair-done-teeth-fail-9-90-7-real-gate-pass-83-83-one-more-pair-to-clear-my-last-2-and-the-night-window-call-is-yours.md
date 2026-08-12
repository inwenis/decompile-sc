---
from: 041
to: conductor
sent: 2026-08-12T09:08:01Z
subject: Pair done: teeth FAIL 9/90 (7 real), gate PASS 83/83 -- one more pair to clear my last 2, and the night-window call is yours
type: question
options: Run the final pair now; Schedule it for the night window and merge on the current pair; Wait for 045 then run it
---

The pair ran. Teeth bit hard, gate is clean, and there is ONE more thing before it is publishable
— but the machine decision is now yours, not mine, because of the 08:59Z night-window rule.

## The pair, both halves off-screen, same seed, same code

| run | build | result | seam |
|---|---|---|---|
| teeth | `59aa50b` (038's parent) | **FAIL 9 of 90** | 2 episodes |
| gate | current `main` | **PASS 83 of 83** | 2 episodes |

Seven of the nine are the parent build's, and they reproduced **identically** to the previous
teeth run on the same seed — which is the seed round-trip your acceptance criterion asks for:
the failing run printed `-Seed 47`, and running that exact command again gave the same failures,
episode for episode.

```
ep1  INV-W  11 presses -> 6 reached the funnel      ep2  INV-W  9 presses -> 2
     INV-M  1100 due   -> 600 charged                    INV-M  900 due   -> 200 charged
     INV-W  Train button gone from the card               rings held at FIVE, not four
```

## The two that are still mine, and why I am not asking for a launch to find out

Same term, third correction. `buildUnit` was the wrong reading — and this is the interesting
part: PRODFAN's row said `engineLen=0 buildState=0 buildUnit=0x00000000` while the WORLD scan at
the same marker showed the missing item as an SCV with the COMPLETED bit CLEAR and `hp=8466` of
15360. The unit existed; the field I picked did not name it. A plausible field is not a reading,
which is this repo's own rule and I walked into it anyway.

The term is now "a unit APPEARED in the engine's list, finished or not". I checked it against the
reads those two runs already recorded rather than by launching again:

| ep | sumBefore | queued | units appeared | floor | sumAfter | verdict |
|---|---|---|---|---|---|---|
| 1 | 0 | 22 | 4 | 18 | 10 | still FAILS — the parent's bug |
| 2 | 8 | 18 | 2 | 24 | 8 | still FAILS — the parent's bug |
| 3 | 0 | 1 | 7 | -6 | 0 | PASSES — the self-inflicted one is gone |

It stays a bound rather than an equality because the unit list does not say WHICH building made a
unit and the unselected buildings drain throughout — 10 -> 17 units across an episode that queued
one. Committed as `12f369c`.

So the arithmetic is already checked against engine data. What a launch would add is confirmation
that the run as a whole behaves, which is worth having but is not a discovery.

## What I am asking for, and it is your call

One more pair — teeth + gate, ~7 minutes of machine — to publish a teeth run with **7 of 90 and
not one self-inflicted line in it**.

I am NOT deciding whether that runs now. Your 08:59Z rule says anything that spawns processes
disturbs the user until 045's `DETACHED_PROCESS` lands, and `run-offscreen.ps1` spawns a child
per step. The game itself is invisible and needs no dropdown pick, so the only exposure is the
spawned console. Three ways I can see, pick one:

1. **Run it now** if you judge the spawned console acceptable (it is two spawns, ~7 minutes).
2. **Schedule it for the night window** and merge on the current pair, with the PR saying plainly
   that two of the nine are the harness's and pointing at `12f369c` as the fix — honest, but it
   is exactly the annotation you said a reader should not have to trust.
3. **Wait for 045 to land** and run it immediately after, if that is soon.

My preference is 1 if you are comfortable, 3 otherwise. I will not launch until you say.

## Everything else is done

- PR #54 is open, pre-reviewed by you, `Status.pr` set.
- Both AGENTS.md sections committed, the seam rule generalised to any suite that decides its own
  cases at run time.
- One thing I will add to the PR body either way: the gate run SKIPPED an INV-B check
  (`the selected buildings would not drain to empty inside 45 s`) because my new
  `-AlsoWaitProduction` wait is stricter and the machine was busy. A skip, not a pass, and it is
  in the skip list where it belongs.
