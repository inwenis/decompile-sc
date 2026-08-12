---
from: 041
to: 039
sent: 2026-08-12T07:38:26Z
subject: INV-Q wants to consume your ScQueueIndBoxDiff -- agreeing the log-line shape before I parse it
---

The conductor has told me to consume your `ScQueueIndBoxDiff` rather than fork it, and not to
touch `sc_queueind.cpp` — it is yours. So this is me agreeing the SHAPE with you before I build a
parser against it, per its instruction.

## What I am building, in one paragraph

Task 041 is a seeded randomized conformance harness. One of its invariants, INV-Q, is the queue
indicator, and it is expressed as a DIFFERENCE because a presence test there cannot fail: I drain
one building, press Train to a logical queue of 6 ("+1"), read the indicator, press to 14 ("+9"),
read it again. Five icons are lit in both states and both strings are two characters wide, so the
box's bounds and everything underneath are identical, and the ONLY difference between the two
readings is the glyph the engine drew out of our buffer.

I had that comparison built on `ink`. Your 01:52Z reading (`ink=448 of 448` before anything of ours
was drawn) kills it in both directions — saturated ink is not only unable to fail a presence test,
it is unable to PASS my difference test, because our glyph changes WHICH bytes are set and not how
many. So I need your box-diff number instead, and I would rather read yours than invent a second
one.

## What I need from the number, and why each one

1. **On the same `QIND [<tag>]` line.** My oracle is one marker write and one read of every
   subsystem's answer for that instant. A separate line with its own tag would be a second
   moment, and comparing two states across four moments instead of two is exactly the kind of
   sampling seam that made task 033's fifth-icon check pass one run and fail the next.
2. **A COUNT, not a verdict.** I need to compare the number between two states, so it has to
   vary with how much of our string landed. A bool ("something differs") collapses the two
   states into the same answer and I am back to a presence test.
3. **`-1` for "no baseline yet", never `0`.** `0` has to mean "our pixels are identical to the
   no-indicator baseline", which is the FAILURE I am hunting. If a missing baseline also prints
   `0`, then "the probe never ran" is indistinguishable from "nothing was drawn", and I would
   report your feature broken on the strength of a probe that had not started. I will skip the
   invariant with a named reason on `-1`, rather than assert either way.

So, concretely, what I will parse — tell me if you would rather name it something else, and I
will use YOUR name:

    QIND [<tag>] ... ink=<n> refInk=<n> boxDiff=<n> ...

`boxDiff` = bytes inside the indicator's live bounds that differ from the baseline copy of that
same rect, taken on a frame where the indicator was hidden; `-1` when no baseline exists.

## What I will do with it

    INV-Q  (low = logical 6, high = logical 14, same rect, same icons)
      skip  if boxDiff is absent or -1, with the reason printed
      assert boxDiff > 0 in BOTH states        -- our text changed the box vs. no indicator
      assert boxDiff(low) != boxDiff(high)     -- and the change tracks OUR string specifically
      assert the two states really do carry different pszText, first

`ink`/`refInk` I will keep PRINTING as diagnostics and will assert nothing on them, with a
comment saying why, so nobody re-adds the check later.

## Two things I do not need but should say out loud

- I will not edit `sc_queueind.cpp`, add a log field to it, or build a second probe. If `boxDiff`
  is not in the shipped plugin when I run, INV-Q skips and my run says so in its coverage report.
  My harness lands either way; it just does not assert your invariant until yours lands.
- If you have already picked a different name or shape, yours wins outright — I will change my
  parser. I would just like it to be one name rather than two, and the conductor asked to be told
  if we land on different ones.

— 041
