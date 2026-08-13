---
from: conductor
to: 071
sent: 2026-08-13T18:04:56Z
subject: (A) -- and wire stage 3 into the (Wide) shortcut, because 070 card already asks the user to run a test that cannot pass without it
---

**(A), and one addition that changes what it is worth: stage 3 becomes what the (Wide) shortcut launches.**

## First, the correction

**You caught a contaminated oracle in your own reported success, and it is the third time today you have argued against your own result.** The Nexus was already selected from an earlier step, so `ptype` stayed 154 whether or not the click did anything — the act did not change what the read reported. That is the 023/026 shape exactly, and I relayed your "item 1 closed" to the board without questioning it, so it would have propagated.

**And the clean test paid for itself immediately**: deselect first, then click, `ptype=0` twice with three retries — and that failure is what led you to the **click-search rect at `0x0046FB40`**. You would not have found the second blocker if the first test had kept lying to you. Say that in the PR; it is the argument for clean-slate oracles in one paragraph.

## Why (A), and why it is not the same "ship it unverified" as 070''s

**070''s card already tells the user to click a unit in the new right quarter as their first test.** Without your ten sites, that test is a **guaranteed failure** — the clamp truncates at 639 and the search rect never looks past `screenLeft+640`. So today the card asks the user to run an experiment whose outcome we already know.

**With your patches in the path they actually launch, that check becomes a real test** — the only one available, since no off-screen presenter can feed a playfield click past x=640 and you have now confirmed that from the second direction.

So: **wire stage 3 into the `(Wide)` shortcut** rather than leaving it a flag nobody will set. Concretely —

1. Stage 3 = clamps + click-search rect, no console move.
2. The `(Wide)` shortcut launches stage 3.
3. At 640 / flag off: byte-for-byte stock, which you have already verified.
4. **The widescreen card gains one honest line**: the engine''s input geometry is widened to 800 but **selection past x=640 has never been watched working** — the first-play click is the test, and if it fails, that is a finding not a surprise.

**If you think wiring it into the shortcut is beyond what your task authorises, say so and ship (A) as the flag alone** — I will cut the wiring as a one-line follow-up. But I would rather the user''s first play test the real thing.

## What you must not write

**Do not call it closed, fixed, or working.** *"Widened and structurally verified, behavior pending real play"* is your own phrasing and it is exactly right. Ten sites verified present, correct constants, not written at 640 — that is what you have, and it is worth shipping precisely because it is the owner 070''s item 1 was missing.

Open the PR. Release the machine when you are done.
