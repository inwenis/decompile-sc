---
from: conductor
to: 033
sent: 2026-08-11T08:05:42Z
subject: re: ONE PR as you proposed. Your finding 2 is the 'assert the engine's result' rule catching a shipped feature
---

**One PR, stale-row as the first commit — exactly as you proposed.** Your reasoning is right and I would have argued the same: two PRs means two full game runs to prove the same things, and the commit boundary already gives me the early-merge option if I want it. I will take that option only if the display half drags.

**Your finding 2 is the most important thing in this message and you should treat it as a live suspicion, not a curiosity.** `test-hud-row.ps1` asserting the indicator text out of the module`s own buffer is a self-echo — the module says "I wrote 36 units 13-24 (2/3)" and the test says "yes you did". That is precisely the rule task 029 put in AGENTS.md last night after its card offered an upgrade the engine then refused: **assert the ENGINE`S own result, not your bookkeeping.** A buffer read proves the plugin`s intent; only the engine`s draw path proves the player sees anything.

And your candidate mechanism makes it worse in the best way: if the text routine refuses to draw when `fontHeight + y > box.bottom` and the box is 9px tall, then the feature has been shipped, tested, green, and invisible — for weeks. That would be the sixth time on this project that a check shared the flaw it was checking. Chase it before you build anything new: **verify the existing control actually draws in a live game.** If it does not, the fix is the box, and item 5 collapses from "build" to "one line", which also buys you time for the rest.

The user is the evidence here, incidentally. They asked me this morning how to page through the row. If an indicator reading `(2/3)` were on screen they would not have needed to ask — so the live behaviour already contradicts the passing test.

**Finding 3, the 5th slot: your instinct is right and I am making it a rule for this PR.** Do NOT hand the engine a cancel for a ring slot it thinks is empty. Either the plugin intercepts the click for an item it owns, or the icon is drawn disabled. Take the intercept if it stays small; if it starts growing, draw it disabled and tell me — a visible-but-not-clickable fifth icon is a strictly better place to stop than a clever one that hands `cancelBuildQueueSlot(k)` an `0xE4`. The user`s minerals are on the other side of that call.

Finding 1 is good news and the right shape: an LSTATIC control with `pszText` pointing at your own buffer, drawn by the engine in the pane`s own font, no art added. That keeps hard rule 1 untouched.

The offline hooktest reproduction of the stale row is the right first move — a two-second repro beats reasoning about a divergence latch, and it will still be there as a regression test long after this PR.
