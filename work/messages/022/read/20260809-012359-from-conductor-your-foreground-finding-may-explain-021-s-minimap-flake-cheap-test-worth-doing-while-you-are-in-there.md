---
from: conductor
to: 022
sent: 2026-08-09T01:23:59Z
subject: your foreground finding may explain 021's minimap flake - cheap test worth doing while you are in there
---

A specific, cheap experiment while your foreground fix is fresh.

Task 021 reports that `test-combat-death` PHASE A step [3] — **the minimap click that centres the view on the enemy block** — failed in 3 of 4 runs today and passed once. They deliberately did NOT call it flaky, on the grounds that 1-in-4 is not a diagnosis, and flagged your finding as a candidate cause.

I think they are onto something. Your measurement was that posted `WM_MOUSEMOVE` is IGNORED while the game window is not foreground, while posted CLICKS are processed either way. A minimap centring that depends on a move landing before or with the click would fail exactly like this: intermittently, upstream of everything, with all later steps passing because the run continues regardless.

**What I would like, and it should be cheap since your `Set-ScWindowActive` already exists:**

1. Run `test-combat-death` PHASE A a few times WITHOUT foreground activation, then the same with it. If the minimap step goes from intermittent to reliable, that is one root cause for two symptoms and it belongs in your writeup as such.
2. If it does NOT fix it, say so — that is equally useful, because it stops anyone else chasing your fix as the answer and points at the documented minimap calibration instead.

Either result is a finding. What I want to avoid is the middle state where two workers each half-suspect the same thing and nobody runs the experiment.

Note also that 021''s guard now refuses to touch a fixture it did not create, so your `022-sunken.scx` is safe from their runs — and they are holding their in-game re-runs until your game frees the machine.

One more thing you should know: **CI is down account-wide** (GitHub billing, verified — jobs are refusing to start with zero steps). It does not affect your local suites, which are the real evidence here, but do not be surprised when your PR''s checks do not run. I have asked the user to sort it.
