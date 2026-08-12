---
from: 039
to: conductor
sent: 2026-08-12T08:04:27Z
subject: Oracle landed + defect arm rebuilt; queued behind two other workers for the machine
---

Progress, no question in this.

1. Tree split as agreed. Two commits on top of the merge:
   - `8a3cec8` the oracle: ScQueueIndBoxDiff (+ its hooktest half, verified to FAIL with the
     fix removed: 0 where it must read 7), refInk''s hidden-control fallback REMOVED per your
     instruction, and a new `surfInk` (whole-surface) as the blindness check that has an
     answer in the drained state where refInk honestly has none. AGENTS.md paragraph written
     into the "read-back of your own buffer" section as the THIRD instance, with the 1330/1330
     and 448/448 numbers.
   - `829209e` the frame probe + a fix 037''s probe needed: its QIND regex is positional and
     this line has gained four fields since it was written, so it would have thrown
     "unparseable" on first read. It parses by name now, and its `ink > 0` assertion is
     boxDiff -- that is the PR #50 weak-evidence note, fixed on our side of the fence.
2. The defect arm is a script, not a hand edit: `work/scratch/039/make-defect-arm.ps1` reverts
   the three behaviours and REFUSES unless each replacement matches exactly once, so a silent
   no-op cannot produce a "defect" build that is really the fixed one. Patch and both DLLs are
   in `work/scratch/039/arms/`.
3. One caveat I am not hiding: in STRIP mode the "+N" box sits inside the very icon this
   module fills, and the baseline predates that fill -- so boxDiff there means "bytes this
   plugin is responsible for", icon and text together. The TEXT-specific oracle in that mode
   is slotDiff (both slots hold the same art, so the string is all that can differ). In GROUP
   mode the band belongs to no control and boxDiff is the text outright. Said in the header,
   in the suite, and it will be in the PR body.
4. Machine: I am queued behind other workers (pids 3736 then 19204) and waiting properly. I
   need roughly 7 runs -- 4 frame probes (barracks/CC x defect/fixed), the two big suites, and
   the group suite''s defect arm for the before picture. If that is too much of the machine
   while 041/043 are running, tell me and I will cut the DEFECT frame runs to the barracks one
   and take the Command Center "2" from the user''s own report instead.
