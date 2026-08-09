---
from: conductor
to: user
sent: 2026-08-09T00:21:36Z
subject: paging = right-click the row; hints: yes but your call; and you were right - my status bar was broken (my fault)
---

**1. How to page through the units.** **Right-click on the bottom wireframe row** — on any portrait in it. Each right-click advances one page, and it wraps around at the end.

Two details that make it easier to use:

1. The indicator text tells you where you are — something like `36 units 13-24 (2/3)`. It only appears when you have more than 12 selected; a normal selection looks exactly stock.
2. **Any change to your selection snaps back to page 1**, which always shows the twelve the engine itself holds. So if you ever lose track, click anything and you are back to a known state.

One caveat worth knowing: right-click only registers on a portrait that is actually filled. On the last page — say 25 units, where page 3 holds one — clicking an empty slot does nothing. Clicking the FIRST portrait always works, since it is populated on every page. (A worker hit exactly this and thought it was a bug; it was aiming at an empty slot.)

**2. Disabling hints to speed up tests — yes, worth doing, but I want your decision on how.**

The complication: the game''s settings live in your Windows registry per-user, not per-installation. So the tests and your own game read the SAME settings. If we turn hints off, we turn them off for you too.

Given that a worker zeroed your sound settings through that exact key today, I have made it a hard rule that nothing we run touches it. So:

1. **You turn hints off in-game** — the tests get the benefit automatically, and you keep control of your own settings. My preference.
2. **We handle it in the test harness instead** — detect the hint dialog and dismiss it, changing nothing global. Slightly slower than not showing it, and a little more code, but zero risk to your settings.

Tell me which and I will pass it to the workers. Not a big win either way — the mission load and the deliberate soak waits dominate the runtime, not the hints.

**3. The status bar: you were right, and it was my fault, twice over.**

I checked instead of guessing, and found two bugs, both mine:

1. `status.json` was **zero bytes**. I had been writing it directly with a truncate-then-write, which races the console''s own atomic writes — one of those collisions left the file empty, and it has been empty since.
2. Even before that, I was writing **invalid state values**. There is a purpose-built script, `set-conductor-status.ps1`, which only accepts `idle` or `processing`. I had been hand-writing `monitoring`, `waiting`, `reviewing` — states the console does not know, so it had nothing to show.

Fixed: file restored, and I am now using the proper script. You should see status again. Ironic given how much of today I spent telling workers to use the tooling rather than hand-rolling their own — same mistake, mine.
