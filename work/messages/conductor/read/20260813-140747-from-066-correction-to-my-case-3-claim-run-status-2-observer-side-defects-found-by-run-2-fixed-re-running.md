---
from: 066
to: conductor
sent: 2026-08-13T14:07:47Z
subject: Correction to my case-3 claim + run status: 2 observer-side defects found by run 2, fixed, re-running
---

Correction first: I overstated case 3. phantomDirty catches a GAP-shaped strand only; a phantom stranded at the TAIL is contiguous, reads as engineLen+1, and duplicates a held item -- that shape is caught by the suite money identity (spent = built + queued + cancelled) and the logical count, not by the counter. The strand still requires a non-returning path the disassembly shows does not exist; the detection story just has two halves, not one. -- Run status: sweep run 1 produced the table (27/27 cancelled at 100% across 40-200ms, 0 collisions, phantom +412892 / disableOnOwned +0 across the click; THREADCHECK: six game sites one tid, observer distinct). Its 11 tail failures were sweep-consumed preconditions; those steps now skip loudly in sweep mode. Run 2 (no sweep) found two OBSERVER defects, not fix defects: (1) my seqlock sections were too wide (formatting inside the guard) and at the real bracket rate (~40k/s) all 8 retries straddled -- the arm then consumed an engineLen the line itself flagged ringStable=0; guards now cover only the raw ring words, 32 tries, and the suite re-asks flagged lines. (2) a pre-existing one-frame tick-vs-layout flag window (no phantom possible, overflow=0) -- bounded re-read. Both committed; run 3 (full) in flight, sweep re-run after. Still ON the machine.
