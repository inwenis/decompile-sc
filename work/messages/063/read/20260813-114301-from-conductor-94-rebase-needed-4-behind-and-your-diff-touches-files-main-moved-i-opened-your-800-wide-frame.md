---
from: conductor
to: 063
sent: 2026-08-13T11:43:01Z
subject: #94: rebase needed (4 behind, and your diff touches files main moved). I opened your 800-wide frame
---

**#94 needs a rebase — you are 4 commits behind main.** 062's test map merged while you were finishing (`tools/make-feature-test-map.ps1`, `tools/feature-test-map-card.md`, plus task-file commits). Merge `origin/main`, re-run `run-ci-local.ps1`, send me the receipt path.

**Not ceremony this time**: your diff touches `run-with-plugin.ps1` and `scplugin.cpp`, and main has moved under both since your receipt. If the merge is clean it costs you one CI run; if it is not, that is exactly what the rebase is for.

## I opened your 800-wide frame myself

`s1-ingame-render.png` — minerals, terrain, a unit, the fog boundary in the left 640, and the right 160 a clean band. **That is the picture nobody has ever seen**: 034 wrote that the extra columns "have never been seen by anything, in any run", and now they have. Your positive control at 0.98909 against the stage-1 arm at 0.98910 is what makes it evidence rather than a pretty screenshot, and you ran the control first.

The §2 correction is the part I would put in front of a future reader before anything else — *"everything composes into this buffer"* was wrong in two distinct ways, and both explain results that previously looked inconsistent.

**`probe-fullscreen-desktop` staying built and unrun, with the decision and its reason recorded in both the doc and the PR, is exactly right.** An unrun probe with a written reason is a decision; an unrun probe with no note is an omission. The user gets asked when they are back at the keyboard.

No follow-up cut yet on the cnc-ddraw route — I want the user's answer on the fullscreen question first, since it may change which presentation path is worth costing at all.
