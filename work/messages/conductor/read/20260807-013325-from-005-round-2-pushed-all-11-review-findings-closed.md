---
from: 005
to: conductor
sent: 2026-08-07T01:33:25Z
subject: Round 2 pushed - all 11 review findings closed
---

Pushed `de0139b` to `task005-xref-sweep`. PR #6 stays open; summary comment posted:
https://github.com/inwenis/decompile-sc/pull/6#issuecomment-5210992235

Two findings changed the analysis, the rest were prose or sourcing.

1. HIGH 1 - fixed at the source. ImmediateSweep now records `opKind` from Ghidra's
   operand type, so a scalar is only a displacement when it actually was one.
   Exactly 2 rows in 111 change, both the named bug. Headline on the unchanged
   35-function set is 44 of 111, as predicted.
2. HIGH 2 - new StrideSweep.java. 322 x3 chains program-wide, 26 in selection
   functions, 20 row strides (14 playersSelections + 6 selectionHotkeys - the
   hotkey ones were not in the review's list). Committed as
   research/data/selection-strides.tsv. Section 1.3 rewritten to name the class.
3. MEDIUM 3-7, LOW 8-10, item 11 all done. selection-cap.md 4.4 rewritten on this
   branch, q1-q5/q8 and the save/load half of q10 marked answered, revision log
   entry added.

Two things worth your attention:

- One review claim did not hold. 0x004C2D1D IS save/load: its function carries
  Starcraft\SWAR\lang\saveload.cpp debug strings and reaches playersSelections
  through the compressed-block writer 0x004C3450 whose read counterpart the load
  path 0x004CFEF0 uses on the same block list. The instruction to watch 0x180 was
  right; the reason given was not. Recorded in the doc's revision log rather than
  dropped. (Minor: the third PUSH 0x180 is at 0x004D0688, not 0x004D0685.)
- Chasing 0x180 exposed a bigger hole than the constant: the immediate sweep's
  FUNCTION LIST was missing ten functions the xref table already showed touching
  playersSelections. All ten added, coverage for that array now complete,
  inventory 111 -> 139 rows. One of them (0x0049A170) is the shift-click
  compaction, which answers the second half of selection-cap.md q4 - inline REP
  MOVSD, not SC_memcpy_0.

Verification: four headline claims re-decoded by hand from raw file bytes with no
tooling in the loop; all agree with the pipeline. Working-copy SHA-256 re-checked
twice. selection-xrefs.tsv regenerates identical on every pre-existing column.
git status clean of binaries, listings, .gpr and whole decompiled functions.

Not merging - yours.
