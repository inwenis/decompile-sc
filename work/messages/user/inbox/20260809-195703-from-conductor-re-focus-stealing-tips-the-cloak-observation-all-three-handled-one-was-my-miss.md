---
from: conductor
to: user
sent: 2026-08-09T19:57:03Z
subject: re: focus-stealing + tips + the cloak observation - all three handled, one was my miss
---

Three things, and I owe you an apology on one.

**1. Focus-stealing — stopped, and being fixed properly.** You are right and it is disruptive. It is the flip side of a fix: the game DROPS our test mouse-movements unless its window is in front, so the tests force it in front — which yanks your window away. I have **paused all in-game test runs immediately** (the three feature workers are doing their static/analysis work instead, no game launches), and cut a task to fix it: run the game on its own hidden desktop, or share input without raising the window, so a test never comes forward over what you are doing. No test will steal your focus again once that lands.

**2. Tips during tests — you are right, we said we would handle it, and it never landed. That is my miss.** I offered two ways to do it earlier and it fell through the cracks. It is now folded into the same fix task. The catch that makes it fiddly: the game''s "show tips" setting lives in the same registry key a worker wiped your volumes through, so it is off-limits — we will dismiss the tip dialog from our side instead of changing your settings. A test run will show no tips, without touching anything of yours.

**3. The cloak observation — thank you, that may be the whole answer.** You noticing the ghosts had no cloak unlocked is exactly the kind of thing that cracks these. I have sent it straight to the investigation with a clear instruction: before concluding anything about Cloak, read the ghost''s researched-abilities out of memory and confirm cloak is actually unlocked. If it was not, then task 022''s "we could not trigger cloak" was measuring a ghost that simply could not cloak — a fixture that forgot to research it, not an engine mystery and not our bug. Ruling that in or out is now the first thing that investigation does.

**Status of the three features while the game is paused:** all progressing on the parts that do not need the screen. Queue-more-than-5 (task 025) is the furthest along — its production-queue work is fully mapped and its offline tests pass (~60 checks: builds in order, paid once, refunds right on cancel and on the building dying). It is essentially done except for one confirming in-game run, which is waiting on the focus fix.

So nothing is stalled — the workers are heads-down on analysis, and the moment the quiet-launch fix lands, they all run cleanly and out of your way. Sorry again about the tips; that one should not have needed you to catch twice.
