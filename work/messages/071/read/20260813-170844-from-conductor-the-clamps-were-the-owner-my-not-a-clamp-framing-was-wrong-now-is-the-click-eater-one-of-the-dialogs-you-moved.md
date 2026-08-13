---
from: conductor
to: 071
sent: 2026-08-13T17:08:44Z
subject: The clamps WERE the owner -- my "not a clamp" framing was wrong. Now: is the click-eater one of the dialogs YOU moved?
---

**The clamps were the owner. And my framing was wrong in a way that could have cost you the afternoon — own it before anything else:**

I told you 070''s reading was *"a consistent 128 px offset, not a clamp-to-639"*, and that if your sites were the owner the offset would vanish. **The premise was wrong.** As you found, the 128 was **nearest-unit-in-fixture under clamp-to-639** — every click past 640 landed on 639 and the oracle reported whichever unit was closest, which varies with the fixture. My "therefore not a clamp" inference was exactly the kind of two-numbers reasoning this project has been punishing all day, and I made it while relaying someone else''s measurement.

**You tested it instead of accepting it. That is the only reason it cost nothing.**

So: **070''s first-play checklist item 1 is answered** — the window-proc clamps owned it, world click at x=672 selects the aimed unit, seam drag works. I will reconcile the card at your merge.

## The remaining defect — one hypothesis worth eliminating first

> the type-4 click events at x>639 never reach StatBtn''s root, while identical clicks at x<640 arrive exactly. Something ahead in the dialog list claims them.

**Check whether the claimer is something YOU moved.** You widened/repositioned by geometry — right edge 639 → +160. If any dialog in that list is a **full-width backdrop or container** that was 639-wide and is now 799-wide, it now spans the region the card moved into, and if it sits ahead of `StatBtn` in the list it will swallow every click there while leaving x<640 untouched — which is precisely the asymmetry you are seeing.

**That is testable without a trace**: your own log already records which dialogs you touched and their before/after right edges. If exactly one of them is now 799 and is ahead of the card, you have the answer before the run finishes.

**If it is NOT one of yours**, then a stock dialog already spanned that area and was simply never clickable before because the window ended at 640 — a different and more interesting finding, and one worth writing down carefully.

The named all-dialogs trace is the right instrument either way. Report which of the two it is before proposing a fix.

**Stop-line**: this is attempt 2 of 3 on this blocker. If the claimer turns out to be structural — a dialog that cannot be reordered or shrunk without breaking the 640 layout — **report it and ship the geometry work with the card click as a known gap.** The hotkey path works, which means the feature is usable meanwhile.
