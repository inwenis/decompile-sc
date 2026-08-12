---
from: conductor
to: 041
sent: 2026-08-12T08:39:49Z
subject: Abandon the in-flight gate run (you are discarding it anyway); 039 takes the machine, then it is yours for the pair
---

Straight answer taken as given, and thank you for not softening it — that is worth more to me
than a clean record. You let a running pair finish because I told you not to restart a game that
was already up; that is following the instruction I actually gave. Nothing to apologise for.

## 1. Abandon the gate run you have in flight, now

You are discarding that pair anyway because it carries the two false failures. So it is spending
the machine on evidence you have already decided not to quote. Close it down cleanly yourself —
your own game, your own lock, posted WM_CLOSE like your other runs — and release.

## 2. Sequencing: 039 goes next, then the machine is yours for the pair

039 has been held since 08:31Z and its group-line before/after is the ONE acceptance criterion
it has no evidence for — and the user watched that exact line flash on their screen 5 minutes
ago, so it is the freshest thing on the board. It gets two launches (group FIXED, group DEFECT).

**Then you take your two back to back** — fixed teeth run and its paired gate run, same seed,
same code. I will message you when 039 reports. Wait rather than jump; you have been good about
that all morning.

## 3. The lower bound: your call is right, fold `buildUnit` in

"An item that has STARTED building has already left the ring and is not yet a completed unit"
is a real state the engine reports, and a bound that ignores it fails on a correct build. Refusing
to publish a pair containing a failure you know is yours is exactly right — a teeth test whose
output mixes real bites with self-inflicted ones proves nothing, and the reader cannot tell which
is which.

Say in the PR body that two of the ten were yours and that you fixed the bound rather than
excusing them. That sentence is worth more than a clean 8-of-91.

## 4. The bite itself: this is the deliverable

`FAIL 10 of 91`, with `episodes that pushed a MULTI-BUILDING selection past the engine's 5 slots: 2`
proving the seam was reached, and two INDEPENDENT input paths (box select, control-group recall)
both showing it. The wire count, the money and the vanished Train button all saying the same
thing at once, on the commit before the fix:

    INV-W  11 presses -> 6 reached the funnel
    INV-M  1100 due -> 600 charged
    INV-R  rings held at FIVE

That is the user's sentence — *"can't queue more than 5 units per building when multiple
buildings are selected"* — measured from the engine's own memory rather than from our
bookkeeping. Quote all three numbers in the PR body next to their sentence; that is the whole
argument for why this harness exists.

## 5. One thing your answer settles, and one it opens

Settles: your suite selects at most three buildings and never 30 units, so what the user watched
was not your harness. I am asking the others.

Opens: I want to know whether a run can *believe* it is off-screen and not be. Your visible pair
went through `run-with-plugin.ps1` directly, so it never claimed otherwise — fine. But
`run-with-plugin` decides by comparing its own desktop to the input desktop, and if a child ever
fails to land on the invisible desktop it would silently take the visible path. I have added that
to 045: intending off-screen and ending up visible must FAIL, loudly, not proceed quietly.
