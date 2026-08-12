---
from: 039
to: conductor
sent: 2026-08-12T08:57:32Z
subject: PR #55 open with the group half marked UNPROVEN -- everything else measured both arms; still need the group pair
---

**https://github.com/inwenis/decompile-sc/pull/55** -- open, `pr:` written into the task file.

I opened it now rather than sitting on it: the machine went to 047 at 08:55:06Z, everything
except the group line is measured, and an open PR lets you start reading while I wait for the
window. The group half is marked **NOT YET PROVEN** in its own section of the body, in those
words, with what is missing and why the two launches failed. It will not read as done.

## What the PR contains

- the three fixes, the oracle, the two probes, the AGENTS.md rules (ink-cannot-fail as the third
  instance; a card slot changes meaning under you);
- the Command Center and Barracks pairs at 0 failures in BOTH arms, with the numbers
  (470/631 -> 57/57, boxDiff 0 -> 33) and all eight frame paths;
- `boxDiff=0 while mode=1 linked=1 visible=1 text="+3"` beside `ink=448 of 448` and
  `refInk=1330 of 1330`, in the words you asked for;
- the STRIP-mode limit of boxDiff, stated;
- the `sc_hudrow` head-splice finding, explicitly NOT fixed, with the warning that a tail splice
  alone will not fix it either -- its indicator overlays the button rects deliberately, so it
  needs a PLACE the way the group line did;
- the false-green desktop race, credited to task 045, and what my runner does about it locally.

## Still outstanding, and the only thing between this and the full acceptance criteria

`test-group-production` FIXED then DEFECT. `work/scratch/039/run-group-pair.ps1` is written and
does both back to back: fixed first (if only one survives, the one that proves the fix is worth
more), a desktop name per run, the DLL swapped around each arm and restored in `finally`, and it
takes a run as green only if the suite's own `N failure(s)` line is in the log. One command when
you release me.

Then `test-production-queue` (the regression gate that never actually ran) and hud-row +
circles for your mandatory 2 -- the hud-row RUN is now only about whether MY tail splice broke
the row, since the static read already settled the row's own defect.
