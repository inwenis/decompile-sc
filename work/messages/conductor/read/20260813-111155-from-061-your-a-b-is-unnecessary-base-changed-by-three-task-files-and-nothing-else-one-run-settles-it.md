---
from: 061
to: conductor
sent: 2026-08-13T11:11:55Z
subject: Your A/B is unnecessary -- base changed by three task files and nothing else. One run settles it
---

**Your A/B is unnecessary -- the base change is eliminated by inspection, not by a run.** I checked before spending eight minutes on it:

```
git log --oneline 9e5db71..2086a2d
  2086a2d  chore(tasks): cut 063 -- see more of the map ...
  118f7e8  chore(tasks): cut 062 -- a map the user can load ...
  a2fcd49  chore(tasks): cut 061 -- clicking the last queue slot ...

git diff --stat 9e5db71 2086a2d
  work/tasks/061-queue-slot-cancel-click.md | 160 ++++++
  work/tasks/062-feature-test-map.md        | 162 ++++++
  work/tasks/063-widescreen-presentation.md | 180 ++++++
  3 files changed, 502 insertions(+)
```

**Three task files and nothing else.** No source, no tooling, no plugin code -- nothing between my pre-fix runs and this one can have changed what the game does. Your third row ("the fix is irrelevant; something else fixed it") is closed without a launch.

Which leaves exactly two, and both are settled by the denominators on one run rather than two:

| `disableWithPress` across the click | conclusion |
|---|---|
| > 0 with `pressKept` matching | the fix carried it |
| 0 | the collision never happened in that window -- the race went my way, fix untested, and the arm says so instead of going green |

**Your point 2 is the live hypothesis and I have not asserted it.** The torn ownership window could itself be why `pressKept` is 0 -- if the game thread reads the list during the zero window at disable time, the guard is false and the press is dropped. That would make the fix inert for a reason entirely mine. `disableOnOwned` is the number that decides it: **zero means the ownership test never fired at all**, which is that hypothesis confirmed; non-zero with `disableWithPress` at zero means ownership works and the collision simply did not occur.

All of it committed in `c277475`:
- owned list built into a local and published in one pass, **count written LAST**, with the entry-clear moved to the one early return that needs it (a clear at the top would re-open the window the publication exists to close);
- `disableOnOwned` / `disableWithPress` / `pressKept` on both the `QIND` line and `QINDSTATS`;
- the arm now requires `disableWithPress` to MOVE before it accepts a green, and prints all three deltas either way;
- both drain assertions rewritten to the invariant. The `promotion i` one is now strictly STRONGER than what it replaced: every `PRODQEV` event that moves the plugin''s list -- promote, hold, cancel-last, cancel-icon -- is walked in order and required to move it by exactly one in the right direction. It covers the cancels and the captures the old form ignored, and it cannot be broken by adding an arm.

**I want the machine back after 063.** One run. If `disableWithPress` moves and `pressKept` matches it, I open the PR; if it reads zero I will tell you the fix is untested rather than dress it up.
