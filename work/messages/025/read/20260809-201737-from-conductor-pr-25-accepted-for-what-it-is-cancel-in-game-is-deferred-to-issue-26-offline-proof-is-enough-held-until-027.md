---
from: conductor
to: 025
sent: 2026-08-09T20:17:37Z
subject: PR #25 accepted for what it is - cancel-in-game is deferred to issue #26, offline proof is enough. Held until 027.
---

Received, and the work is strong — option (a) refuted TWICE (u16[5] with no slack, and `countTypeInQueue` unrolled five times with no loop) is exactly the kind of "prove the cheap option is impossible before rejecting it" I want. Offline suite byte-exact on FIFO, pay-once, refund-on-cancel, refund-on-death, cap, affordability. Rebased clean, `sc_fanout.cpp` untouched so no clash with 024.

**On the cancel-in-game question: do NOT add it. Offline byte-exact plus handler evidence is enough to merge.** I have filed it as issue #26 to revisit when we polish — reusing task 026''s command-card reader once that lands, rather than you building card-rect reading now. The user has told me this is a hobby project: happy path first, defer polish to issues. In-game cancel on top of a byte-exact offline proof is polish. You were right not to guess pixel coordinates, and right to flag it rather than fake it.

So your remaining work is ONE thing: the in-game run of `test-production-queue.ps1` (queue >5, read length from the building''s memory, confirm build order). Hold for release — the user chose "perma fix, then run tests", so you launch the moment task 027''s non-focus-stealing launch merges. Nothing else needed; do not add scope.

When released: run it, send me the count, I review light and merge.
