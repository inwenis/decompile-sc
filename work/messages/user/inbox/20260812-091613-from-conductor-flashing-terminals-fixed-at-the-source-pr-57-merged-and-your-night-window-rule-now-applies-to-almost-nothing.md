---
from: conductor
to: user
sent: 2026-08-12T09:16:13Z
subject: Flashing terminals fixed at the source (PR #57 merged) -- and your night-window rule now applies to almost nothing
---

045''s part 0 merged — and the flashing terminals are gone at the source.

## What changed

Spawned helper processes now use `CREATE_NO_WINDOW` instead of asking Windows for a new console.
No console is created, so there is nothing for Windows Terminal to draw on your desktop, on any
desktop. Measured rather than asserted: 19 console/Terminal processes before a spawn, 19 after,
with a marker file proving the child script still ran start to finish.

That last part matters, because the first fix we tried did NOT do that — `DETACHED_PROCESS` made
PowerShell exit 0 without running the script at all, which would have quietly broken every
off-screen suite while looking like a pass. 045 caught it by testing the thing I told it to ship.
The rejected approach is written into the code comment so nobody repeats it.

**Consequence for you: your night-window rule now applies to almost nothing.** Off-screen runs
disturb nothing, so I have released 039''s remaining regression runs to today rather than 23:00.
What still follows the rule: any run that must go `-Visible` for a game-type dropdown, which is a
real game window on your screen. Those are still announced to you first — and task 049, just cut,
is producing the list of exactly which suites need it.

## Also merged since I last wrote

- **PR #56** (task 047): the test that asserted "6 hooks installed" when the plugin legitimately
  installs 7 now asserts the hook SET BY NAME. Add a hook tomorrow and it either passes because it
  is listed, or fails naming the hook that appeared. It stops being a number that rots.
- **PR #53** (task 046) earlier: two stale log-parsing patterns that had silently stopped matching
  anything.

## Where your two bugs stand

- **5th slot garbage:** proven fixed for both buildings you named, before/after frames on disk —
  paths in my 08:49Z message. PR #55 is open with the group-line half honestly marked NOT YET
  PROVEN; 039 is running that pair now.
- **Text behind the icons:** diagnosed. The row indicator is spliced at the HEAD of the dialog''s
  child list and deliberately overlays button rectangles that repaint intermittently — which is
  the flicker, by design rather than by accident. It is a different module from the one 039 is
  fixing, so it gets its own task with the diagnosis already done.
