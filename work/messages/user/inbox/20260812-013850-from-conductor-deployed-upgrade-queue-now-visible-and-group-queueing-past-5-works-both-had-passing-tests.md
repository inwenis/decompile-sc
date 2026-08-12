---
from: conductor
to: user
sent: 2026-08-12T01:38:50Z
subject: Deployed: upgrade queue now visible, and group queueing past 5 works (both had passing tests)
---

# Two of your four bugs are fixed and deployed — relaunch your shortcut

Both were real, both were in shipped code, and both had passing tests. Details below,
because in each case the *test* is the more interesting failure.

## 1. What to try right now

| try this | expected |
| --- | --- |
| Engineering Bay, queue 3 upgrades | **"+3 upg"** at the bottom-right of the status pane |
| Box 3 Command Centers, press Train 9 times | 9 units queued, 9 charged — not 5 |
| Right-click the unit row with 13+ units selected | flips to the next page (this already worked, nobody told you) |

Deployed version `ec097c7`. Your saves, replays and characters were not touched.

## 2. The upgrade queue: it never worked anywhere, on any building

Not an Engineering Bay problem. The code that decides *where on screen* the indicator
hangs had no case for upgrades at all, so it returned nothing, and the drawing step read
that as "nothing to show" and reset itself — every building, every game, since it shipped.

Its test passed because the test asked the composer "what text would you write?" and the
composer answered correctly. Nothing ever checked that the text reached the screen.

## 3. Queueing past 5 with a group: two arrays, side by side, one wrong

The plugin worked out which building a Train command was for by reading the **client's**
selection list. The engine gates on a different list — the **simulation's**. The two sit
next to each other in memory, are the same shape, and hold the same thing whenever you
have exactly one building selected.

Which is every case any test had. So it passed for two whole features.

Fan-out is precisely where they disagree: the simulation holds one building at a time
while your screen still holds the group. The plugin concluded "no single building here",
held nothing back, every ring filled to 5, and the game stopped sending. Measured before
and after, 3 Command Centers, 9 presses:

- before: **5** of 9 reached the game, 750 minerals
- after: **9** of 9, 27 units, 1350 minerals, charged by the engine, cancel refunds exactly 50

## 4. Still running

1. **The 5th-slot garbage** — root cause found, and it is one bug, not three. We fill the
   slot the game had already laid out as *empty*, and leave one field pointing at the
   button-border artwork, so it draws frame #unit-type out of the wrong art file. That is
   why it is a "2" on one building, black on another, blue flashing on a third, and why
   none of them change as the queue grows. Also fixing the queue text hiding behind the
   icons — that one is paint order, not position.
2. **Your screen** — the VM answer is turning out better than a VM. Windows 11 Home has no
   Hyper-V, but the game can be run on a *separate Windows desktop object* that never
   composites to your monitor. Zero install, being live-tested now. VM stays as the
   fallback.
3. **Your randomized testing idea** — running, and it has to prove itself: before it counts
   as done it must rediscover the group-queueing bug above when pointed at the code from
   before the fix. A generator that cannot find a bug we know about would get trusted
   anyway, which is worse than not having one.
4. A fourth worker is fixing the same wrong-array mistake in the upgrade code before it
   ever reaches you — it is harmless today only because upgrades are never fanned out.

## 5. One thing that is still yours

GitHub Actions is refusing to run: *"recent account payments have failed or your spending
limit needs to be increased"*. Every merge tonight was gated on a full local run of the
same checks instead, with a receipt tied to the exact commit — so nothing was waved
through. But it is your billing page, not something I can fix.
