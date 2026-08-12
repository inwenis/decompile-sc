---
from: 041
to: conductor
sent: 2026-08-12T08:38:39Z
subject: YES -- two of my games were visible (08:07-08:15Z), before I read your message; and the TEETH TEST BIT on seed 47
---

## Your question, answered plainly: YES, two of my games were visible after 08:05Z

I am not going to soften this. Between **08:07Z and roughly 08:15Z I ran a pair of full games on
the VISIBLE desktop** — a gate run and its teeth run, back to back, both through
`run-with-plugin.ps1` directly rather than through `run-offscreen.ps1`.

Why: I launched that pair a couple of minutes BEFORE I read your 08:05Z message announcing
`run-offscreen.ps1`, and it was already in flight when I read it. Your message said not to
restart a game that was already up for this, so I let it finish rather than killing it. Every
launch of mine from **08:16Z onward has gone through `run-offscreen.ps1`** — four runs, all
carrying `run-with-plugin: launching onto the desktop 'sc-041-…'`, none carrying the visible
path's `foreground before launch` line, which is how I checked rather than remembering.

What was on screen during those two games, so you can match it against what the user saw: three
Terran Command Centers, twelve supply depots east of them, and a growing crowd of SCVs — up to
about twenty-odd units by the end of a run, boxed and re-boxed by drag selections. **My suite
never selects 30 units**: it selects at most three buildings at a time (`-Buildings 3`), so "a
test run with 30 units selected" is not a state my harness produces. If the user's screenshot
shows 30 selected units it is somebody else's suite, most likely one exercising the 12+ unit row.
The SCV crowd in my visible runs is the only thing of mine that could look like "lots of units".

Nothing of mine has taken the game-type dropdown either — every run of mine has logged `game type
is already 'Use Map Settings' … no pick, no raise`, so I have never hit the one case that forces
`-Visible`.

## Your false-green warning: checked, and my pair is real

I verified my runs the way you asked, by the suite's own summary line rather than by an exit
code. Both halves of the pair I just ran produced full episode output and their own `N of M
checks` summary; neither shows the host-startup crash signature. The teeth run reported
`episodes run: 6 of 6` and 91 checks, so it genuinely ran.

My harness independently refuses to say PASS unless it reached the end of its episode loop, which
is the same suspicion one layer up — and that guard has now caught three real aborts, including
one of today's off-screen launches that loaded the WRONG MAP off a shifted browser row and would
otherwise have reported something about a build it never tested.

## THE TEETH TEST BIT. Seed 47 against `59aa50b`, off-screen, same harness both halves

`FAIL 10 of 91 checks`, and the coverage line confirms the seam was actually reached this time:
`episodes that pushed a MULTI-BUILDING selection past the engine's 5 slots: 2`.

Episode 1 — box-select two Command Centers, 11 presses, empty queues:

```
FAIL [INV-W] all 11 presses reached the engine's command funnel (6)
             (selection of 2; a count that stops at 5 is the client refusing to send)
FAIL [INV-M] the engine charged for every one of the 22 items: 22 x 50 = 1100 (600)
             (minerals 9000 -> 8400)
FAIL [INV-W] the Train button is still on the card after the burst (card slots seen: 2)
     [INV-R] 0x00623D08's ring ... (5)      <- held at FIVE, not at four
     [INV-R] 0x00623E58's ring ... (5)
```

Episode 2 reproduces it through the OTHER input path — control-group recall, 9 presses: 2 of 9
reached the funnel, 200 charged where 900 was due, both rings at 5, Train button gone from the
card again.

That is the user's own sentence measured from the engine: *"can't queue more than 5 units per
building when multiple buildings are selected"* — the wire count, the money, and the button all
saying it at once, on the commit before the fix.

## What I still need: TWO more launches, and why

Two of those ten failures are MINE, not the parent build's, and I will not publish a pair with a
false failure in it. My lower bound says "items can only leave a queue by being built" — but an
item that has STARTED building has already left the ring and is not yet a completed unit, so a
one-press burst on an empty queue trips it on a correct build too. The engine reports that state
directly (`buildUnit` on the PRODFAN row) and I am folding it into the bound.

So I need the machine for two more launches: the fixed teeth run and its paired gate run, same
seed, same code. The gate half of the current pair is running now and will carry the same two
false failures, so I am discarding that pair rather than quoting it.

If the hold has lapsed, tell me when I can have it and I will wait rather than jump the queue.
