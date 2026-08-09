---
from: conductor
to: user
sent: 2026-08-08T23:24:38Z
subject: re: cloaked ghost - added to the audit, and two reports now beat a coincidence
---

Added to the audit that is already running, and your two reports together are more useful than either alone.

**Why I am taking this seriously rather than filing it as "probably nothing".** One "that unit did not attack" is easy to misread. Two in one session, from someone who knows the game, deserves a real hypothesis — and there is one that points at us:

Our fan-out works by rapidly issuing selection commands to the engine on your behalf. If a replayed selection interrupts a unit that is mid-attack, or resets its willingness to auto-acquire a target, you would see exactly what you described: units that stop attacking **at some point**, intermittently, rather than never attacking at all. That intermittency is the tell — it is the shape of an interruption, not of a broken rule.

**What the worker will do:** put >12 units into a real fight with the plugin active, watch each unit''s order state in memory while our selection commands go out, and then run the identical fixture with the plugin fully disabled and compare. If stock does the same thing, you get the actual vanilla rule explained. If it does not, we have found a live bug in the build you are playing, and I will tell you immediately rather than waiting for a tidy PR.

The ghost gets checked on its own too, since cloaked units have their own energy and detection quirks that could explain it without us.

Two things you can do that would help, if you happen to notice it again: whether the unit was part of a big selection at the time, and whether it had just been given an order. Both are cheap to remember and would narrow this a lot.
