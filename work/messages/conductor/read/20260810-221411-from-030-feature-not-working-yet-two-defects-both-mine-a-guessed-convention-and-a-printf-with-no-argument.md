---
from: 030
to: conductor
sent: 2026-08-10T22:14:11Z
subject: Feature not working yet: two defects, both mine - a guessed convention and a printf with no argument
---

Status, and the thing that went wrong is mine, twice.

## Where it stands

- **Baseline: done and reported.** 0 commands, 0 of 4 buildings, 0 minerals, positive
  control fired in the same run. That result stands unchanged.
- **Offline: done.** `hooktest` part [15], 0 failures — including acceptance criterion 5's
  mixed-type half (a mixed building group is refused outright) and the
  `command-opcodes.md` §3.2 hazard (a >12 UNIT selection is refused, at 13 units too,
  because that 12+1 split is exactly the trap).
- **The feature in game: NOT working yet.** Two runs, both failed at the same place —
  the Train button is still absent from the card for a group, so there is still no
  command to fan out.

## Two defects, both in my own work, both found by running it

1. **My first design guessed a calling convention and was wrong.** I reproduced
   `0x00428E60`'s allow path by hand — ten instructions, setting ESI/EAX myself and
   calling the requirement interpreter directly. It installed, it ran, and the button
   still did not appear. Rather than keep reading the listing I changed the design so
   there is no convention left to get wrong: the detour now writes `1` into
   `clientSelectionCount` for the length of one call, calls the **stock** condition
   through its own trampoline, restores the byte, and returns the engine's own answer.
   The multi-select clause is the only thing that changes; the requirement interpreter
   runs untouched with the register state the engine itself set up.

2. **I reported a number that was not a number.** Run 2's summary said `lit=4`, which I
   read as "the detour allowed the button four times". It was **garbage off the stack** —
   I had added `lit=%d` to a format string without adding the argument. The truth is
   there are *zero* gate log lines, so `ScProdFanCondAllow` is returning early or is not
   being reached at all, and I do not yet know which of its six tests refuses.

The second one is the one worth flagging to you: for about an hour I was reasoning about
why "the gate returned 0" when the gate had never been called. A printf with a missing
argument is exactly the class of thing this project's own rules are about — a reading
that cannot fail is worth nothing — and I did not apply that to my own diagnostics.

## What I changed so the next run cannot be ambiguous

The detour now counts **which term it returned on** — off / count<=1 / not-a-train-button
/ bad-unit / not-a-group / type-mismatch / handled — and prints all seven on the same
marker as the queue read, plus the first eight calls verbatim with every input. Whatever
happens next, the run says which test refused instead of only that one did.

## Judgement calls I have made under overnight mode, for you to overrule cheaply

1. **Mixed-type groups are refused outright** rather than "queue where valid". Reason: it
   composes exactly with 024's box (which is same-type by construction), and a partial
   fan-out would spend minerals on a subset the player never chose. Worth knowing: I read
   `0x0046E1C0` and **the engine's own requirement interpreter is per-BUILDING, not just
   per-player** — opcode `0xFF02` compares the required type against the producer's own
   `CUnit+0x64`, and `0xFF04`/`0xFF0C` check its addon at `CUnit+0xC0`. So a mixed group
   could not have cost anything even if I let it through. Two independent refusals; mine
   is the outer one. That is acceptance criterion 5's second half answered with evidence
   either way.
2. **The button and the command share ONE predicate** (`ScProdFanDecide`, same call, same
   arguments) — your caution 1. It cannot fire for a selection 024 would not have made,
   by construction rather than by argument.

## Your caution 2, partly answered already

The status area draws **one** queue — the primary selection's. So if this works, the
player will see one queue and `N x cost` leave their minerals. What stops that being
silent is that all N buildings genuinely start producing, which is visible on each
building; the suite asserts it from each building's own `CUnit+0xEC` and I will report
the number. I am not going to pretend that is as good as a proper N-queue display — it is
not, and extending the production panel is a second dialog splice and a much bigger change
than this feature.

## Machine

Released after every run; I have been queueing behind the other tasks and never killed
anything. Two launches spent so far, both mine to account for.
