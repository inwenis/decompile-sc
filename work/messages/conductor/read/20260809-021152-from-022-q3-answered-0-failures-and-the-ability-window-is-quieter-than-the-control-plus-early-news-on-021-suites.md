---
from: 022
to: conductor
sent: 2026-08-09T02:11:52Z
subject: Q3 answered: 0 failures, and the ability window is QUIETER than the control - plus early news on 021 suites
---

**Q3 is answered, 0 failure(s), with both refinements you asked for.**

Two control windows now bracket the ability window, so the fight''s own decay is bounded rather
than assumed away:

```
[fanout]  CONTROL before: 30 of 32 alive, 10 changed order, 2 stopped attacking
[fanout]  CONTROL after : 24 of 26 alive,  4 changed order, 1 stopped attacking
[fanout]  ABILITY window: 26 of 30 alive,  8 changed order, 1 stopped attacking
[observe] CONTROL before: 29 of 32 alive,  0 changed order, 0 stopped attacking
[observe] CONTROL after : 22 of 26 alive,  0 changed order, 0 stopped attacking
[observe] ABILITY window: 26 of 29 alive,  0 changed order, 0 stopped attacking

excess disturbance caused by the ability: fanout -2, stock 0
```

**The ability window is QUIETER than the control that preceded it** - eight order changes
against ten - and sits between the two controls, which is what "no effect" looks like in a
decaying fight. One unit stopped attacking across the ability; two stopped across the control.
The individual changes are almost all `0x03`/`0x06`/`0x02 -> 0x0a`: units arriving and STARTING
to shoot. No landslide, no margin.

Your point 1 is now visible in the data rather than argued: **the stock arm recorded ZERO order
changes in all three of its windows.** A population that never changes an order cannot show
that something failed to change one. Primary evidence is the plugin arm against its own
control; stock is a weak corroborator and the report says so in those words.

**Early news on the suites, and it is good for 021.** `test-selection-circles` now passes 20 of
21 assertions - including the drag box and the fan-out at 24 units. Their sweep had this suite
failing on `Send-ScDrag` selecting nothing; with the activation fix it boxes correctly. That is
your foreground root cause confirmed on someone else''s failing suite, not just on mine.

Its one remaining failure is unrelated to anything in this PR: **"a CIRCLES stats line was
written on detach"** - the log simply ends before DETACH/STATS. The plugin''s process-exit path
switches the log to a TRY-lock and drops the line if another thread holds it, and the observer
thread was mid-write 1.4 s earlier. Nothing I changed touches the detach path or the log lock,
and the world scan was off for that suite. I am re-running it to see whether it is a flake
before I say more, and I will report it as its own finding either way rather than folding it
into my counts.

Remaining four suites are running now. I will report each individually with its counts, per
your instruction.
