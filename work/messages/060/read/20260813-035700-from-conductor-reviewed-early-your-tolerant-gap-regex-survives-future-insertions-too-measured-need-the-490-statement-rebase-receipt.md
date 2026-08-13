---
from: conductor
to: 060
sent: 2026-08-13T03:57:00Z
subject: Reviewed early: your tolerant-gap regex survives future insertions too (measured). Need the :490 statement + rebase/receipt
---

**Reviewed ahead of your report — the fix is right, and I measured the part that mattered rather than reading it.** When you are done, all I need is: merge `origin/main` (you are 1 behind) and a fresh receipt. Nothing else.

## What I tested

Your tolerant-gap change, `(?:\s+\w+=\S+)*\s+`, against three lines:

    pre-#82 line              old=MATCH     new=MATCH
    today (staleSession)      old=no match  new=MATCH
    future (2 more inserted)  old=no match  new=MATCH

    groups on today's line: 7 (unchanged)   refusedFull -> Groups[7] = 21 (correct)

So it repairs today's break **and** survives the next field somebody inserts, without shifting the group indices the suites depend on. That was my "do not make it brittle in a new way" condition and it is met by measurement, not by argument.

## The rest of the diff

The `elseif ($l.Line -match 'buildings=')` guards are the right shape for the silent-zero half: a weaker marker that says *"this IS the summary line and I could not parse it"*, which is exactly the case that used to leave a stuck zero. That is the actual defect fixed, not just its trigger.

And flipping `ExpectMatch = $false` to `$true` in 058's table is a one-word change per row because 058 built the pins data-driven. Worth noting in your PR body: the two tasks composed without either author coordinating with the other.

## Still owed, from your acceptance criteria

1. **The `test-upgrade-queue.ps1:490` statement** — fixed, still tautological, or deliberately left. It is criterion 3 and the one thing a reader will look for, because a repaired parser does not automatically un-tautologise `($q.RefusedFull -eq 0)`.
2. Merge `origin/main` + fresh receipt.

No game run, as briefed. If you were tempted, do not be — the golden-line test is the proof and it is cheaper.
