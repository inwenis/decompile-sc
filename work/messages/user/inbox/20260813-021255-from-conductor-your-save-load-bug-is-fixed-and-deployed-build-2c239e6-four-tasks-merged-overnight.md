---
from: conductor
to: user
sent: 2026-08-13T02:12:55Z
subject: Your save/load bug is fixed and deployed -- build 2c239e6. Four tasks merged overnight
---

**Your save/load bug is fixed and deployed.** Everything below happened while you slept; nothing needs your input, and nothing is broken.

## The headline

**Build `2c239e6` is on your desktop shortcut.** The over-cap queue no longer follows you into a loaded game — the workaround I gave you (quit to menu before queuing over the cap again) is retired.

Verified from the run's own output rather than a worker's report:

    ATTACH banner confirms the running plugin is 919e802
    COVERAGE  overflow held at save time = 3 -- this arm DOES reach the over-cap seam.
    ok  arm6: the plugin holds NOTHING for a game it never queued in (overflow=0, tracked=0)

The coverage line matters as much as the tick: an arm that saved with nothing over the cap could not have detected this at all, and one did reach the seam. The plugin now says so out loud when it drops them:

    dropping 1 building record(s) holding 3 item(s) queued in a game that has ended
    -- NOT refunded (those minerals were spent in that game, not this one)

## Four tasks merged overnight

| # | what | why it mattered |
| --- | --- | --- |
| 053 | the merge gate itself | it could attest a pass for a run that failed — and with Actions down it was the *only* gate |
| 056 | build identity | a green run can now name the commit it tested; two builds of one tree are byte-identical |
| 055 | the vacuous-assertion sweep | eleven checks that couldn't fail, five issues closed |
| 054 | the game-session epoch | your bug, plus six siblings of it, plus a seventh nobody knew about |

## Three things found that nobody was looking for

1. **A hang in your game.** 054 found that appending an already-linked control writes `next = self`, which sends the engine's own redraw walk into an infinite loop — inside the game's paint, with no plugin code on the stack to blame it. Closed on the way past.
2. **A seventh cross-game survivor.** `sc_queueind` keyed its screen baseline on a heap address the engine reuses between games, so task 039's own oracle could diff one game's surface against another's — failing by producing a *plausible number* rather than a zero. Your merged fixes were not affected (single-game runs), which I checked rather than assumed.
3. **An absence check that could spell only 1 of 4 hook names.** *"NOT ONE hook is installed"* would have passed on main today with a hook spliced.

## Where I was wrong, twice

- I called 054's negative control a regression. It had deliberately run the pre-fix build to show FAIL→PASS; the hook lists in its own logs proved it and I had not read them.
- I told 054 its `7/7` hook count was a missing counter. It is not — that line is `sc_fanout`'s own rollback check and has always counted 7 of the plugin's 22. Its fix was better than either option I offered.

Both times the worker corrected me with evidence and I checked the evidence rather than the seniority. That is working.

## What is running now

**057** — making a falsifiable oracle cheap. 055's finding was that *a vacuous check costs a line while an honest one costs a task*, so it is building the script that makes "watch it fail" a three-minute job. No game needed.

## Waiting for you, whenever

1. **Play it.** The fifth production slot, the >12-unit page indicator, and now save/load. All three of your reported bugs are in this build.
2. **Nine issues** are open from the architecture review and tonight's work. None urgent.
3. The scheduled-review question from last night is still unanswered and still not blocking.
