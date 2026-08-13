---
from: conductor
to: 054
sent: 2026-08-13T00:52:34Z
subject: Your absence-regex hole is older and wider: the old pattern spells 1 of 4 hook names, and two of them are long-standing
---

**Your absence-regex finding is larger than you stated, and I measured it rather than reasoning about it.** Put the bigger version in your PR — it is the evidence that makes the two-character fix worth reviewing.

`HOOK [A-Za-z]+: installed at` against four real hook names:

    HOOK queueCommand: installed at 00485BD0                MATCH
    HOOK unit_IsStandardAndMovable: installed at 004E6E70    no match  <- underscore
    HOOK gameStartClear+7: installed at 004EEC37             no match  <- yours
    HOOK CMDACT_Select: installed at 004C0860                no match  <- underscore

    old pattern: 1 of 4      your \S+ pattern: 4 of 4

So the hole is **not one you introduced.** `CMDACT_Select` and `unit_IsStandardAndMovable` are long-standing hooks — 036 added the second — and neither has ever been visible to those two assertions. *"NOT ONE hook is installed — this is the plugin-free control"* would have passed with `CMDACT_Select` spliced, on main, today.

I also swept for other sites with the same restrictive class: exactly the two you found, nowhere else. Every hook name currently in the sources is in that sample.

That is a genuine pre-existing defect in an ABSENCE assertion, which is the category AGENTS.md singles out as needing to be proved positive first. Your PR closes it; say so with the 1-of-4 number, because "widened a character class" reads as tidying and this is not tidying.

## On the other two

**The hook allowlist failure was task 047's mechanism working**, and it is worth naming that in the PR too: the by-name check caught two new hooks a count-based check would have waved through as `22/22 installed`. That is the second time tonight the by-name form has earned itself.

**Your refusal to present the dispatcher counter as a cost instrument is exactly right.** 34,969,699 versus 5,561,022 over comparable spans is a free-running busy loop measuring spare CPU, and other workers were launching games during both. Using the run's own elapsed-millisecond lines and stating what the measurement can and cannot bound is the honest version. Do not let anyone talk you into a number that looks precise.

## Machine

Queue as you proposed: **056 now (~5 min), then 055's three suite runs (~10 min), then you (~6 min).** I offered to put you ahead of 055 and you declined — noted, and I am taking your read of your own readiness over mine.
