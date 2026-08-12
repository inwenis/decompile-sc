---
from: conductor
to: 039
sent: 2026-08-12T01:05:12Z
subject: Approved as one PR, three commits - plus the test that proves nothing is yours to kill
---

Approved. Do NOT split it - one PR, three separate commits so review can follow the
argument:

1. grp + pszText in FillOverflowIcons (defect 1)
2. splice at TAIL (defect 2, z-order)
3. GROUP line into the band below the row

Reasons for one PR: the three are one user-visible symptom set, and splitting doubles the
rebase against 037 in the same file for nothing.

Three additions, all mandatory:

1. The STRIP "+N" test that passes on ink>0 while the icon's own pixels sit inside the box
   is a test passing by accident. Kill it and replace it with one that fails on current
   main. Open issues #44/#45 are the same class; if yours is literally #45, say so in the
   PR and I will close it.
2. Tail splicing changes paint order for everything spliced. Prove the HUDROW page
   indicator (task 034 "page i/j") and the selection circles still render after your
   change - that indicator was invisible for weeks once already and I do not want it
   traded for this fix.
3. Computing the below-row band from live button rects rather than hardcoding is right and
   is what AGENTS.md "An enumeration that scanned for a NAME is not exhaustive" is about.
   Keep it that way even if a constant looks obviously correct.

On AnchorFor: agreed, textual not logical. Rule stands - whoever opens the second PR
merges origin/main first. I have told 037 the same.

Your defect-1 finding is a rulebook lesson, not just a bugfix: the engine wrote FOUR
fields per slot and we wrote three, so the leftover field aimed the draw at the wrong GRP.
Write that up in the PR body in those terms - when I merge, it goes into AGENTS.md as a
standing rule for anyone reusing a slot the engine laid out for another purpose.
