---
from: 039
to: conductor
sent: 2026-08-12T07:33:37Z
subject: What 039 is holding after the reboot: 3 fixes committed, a NEW oracle uncommitted, and the defect arm still in the tree
---

Reconstructed from disk only (no chat context survived). What the worktree holds:

## Committed (4 ahead of origin/main, no PR)

- `df97c83` defect 1 — write the GRP + pszText the fifth icon's frame index means
- `569237d` defect 2 — splice at the TAIL so the line paints over what it overlays
- `35327a8` defect 3 — GROUP line into the band below the row, measured off live button rects, or draw nothing
- `101ba50` merge of origin/main (037 + 038) — your 01:39Z instruction was carried out before the reboot

## Uncommitted — TWO different things mixed in one dirty tree

1. KEEP: a new oracle. `ScQueueIndBoxDiff` + a baseline copy of the indicator's box taken
   on the game thread on frames the indicator is HIDDEN. Reason, from the predecessor's own
   live run at 01:52Z: `ink` CANNOT FAIL in this dialog — the pane's art is in the same
   surface, so the probe read `refInk=1330` of 1330 bytes over a queue icon and `ink=448` of
   448 inside the indicator's box before anything of ours was drawn. That is your mandatory
   addition 1 (the "+N" test passing by accident) — same class as #44/#45. Both suites are
   already switched over to assert `boxDiff > 0` instead of `ink > 0`.
   Also in this bucket: `refInk` falls back to a hidden control instead of reporting -1,
   which is a real FAIL in the run below.
2. TEMPORARY: three source reverts that rebuild main's behaviour — head splice (`if (1)`),
   anchor-relative placement, and dropping the grp/pszText writes. That is the DEFECT ARM,
   not work in flight. `work/scratch/039/arms/{defect,fixed}-scplugin.dll` (01:48Z / 01:58Z)
   are its build products.

## What was already measured, and what was not

- DEFECT arm ran 01:52Z–01:54Z: `C:\sc-work\logs\039\before-suite-output.txt`, 6 failures.
  Three of them are exactly the defect-1 signature and are the "fails on current main" half:
  `art=B` (the button-border GRP, so the frame index means nothing), no slot label, and
  `slotDiff=773` bytes between slot 0 and slot 4. Two more are a `[plugin-cancel]` pair with
  a unit completing inside the measurement window (the AGENTS.md confound class — I will not
  publish a run in which that happened). One is the `refInk=-1` oracle hole above.
- That run PREDATES the boxDiff oracle, so there is no defect-arm evidence yet for defects
  2 and 3, and no FIXED-arm run happened at all. The 01:58Z fixed DLL was built and the
  machine rebooted five minutes later.

## Plan

1. Split the dirty tree: commit the oracle (commit 4), keep the three reverts as a patch in
   `work/scratch/039/` so the defect arm is rebuildable, never committed.
2. Both arms on the merged tree, same suites, same oracle, DLL the only difference.
3. Terran frame capture for the user's own three cases — Command Center, two Barracks
   queuing different unit types, which under defect 1 is what makes three DIFFERENT wrong
   pictures out of one bug — before and after, plus the group selection, under your 07:32Z
   standing rule, into `C:\sc-work\logs\039-frames\` with state names.
4. Then HUDROW `page i/j` and selection circles after the tail splice (your mandatory 2),
   with frames.

Machine: task 043 took the launch lock at 07:29:33Z. No StarCraft process right now; the
suites' lock waits for another worker rather than colliding, so I will let it.
