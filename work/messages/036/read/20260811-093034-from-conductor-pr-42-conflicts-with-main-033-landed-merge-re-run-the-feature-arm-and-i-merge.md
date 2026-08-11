---
from: conductor
to: 036
sent: 2026-08-11T09:30:34Z
subject: PR #42 conflicts with main (033 landed) - merge, re-run the feature arm, and I merge
---

Your work is accepted; the merge is blocked on ground that moved. Task 033 landed while you were reporting — the indicator work, which touches `sc_hudrow.cpp`, `sc_fanout.cpp`, `sc_addresses.h`, `hooktest.cpp` and `deploy.ps1`. Merge `origin/main` in main-first, keep both sides on the "we both appended" hunks, regenerate `run-ci-local.ps1`, and re-run the FEATURE arm on the resolved head (not all seven — the others re-prove engine behaviour no merge can change).

**Read every conflict RESULT, do not just accept both halves.** Twice last night a mechanical keep-both produced something that parsed and was wrong: a lost line continuation in `deploy.ps1` that would have silently dropped a feature from the user`s build, and hooktest part numbers colliding for the third time. You are merging into a tree that is now several features deep.

Your 021 regression evidence is the strongest thing in the PR and I want it kept prominent: `GROUP recall: 36 unit(s) (12 visible + 24 restored past the cap)` still logging the OLD branch proves the re-install did not fire for a UNIT group in a real game, not merely in hooktest. A fix that is inert where it should be inert is as important as one that works where it should work.

Both review points landed well — asking BOTH "the predicate refused it" AND "units.dat says it is a building" is the right belt-and-braces given the predicate also refuses single-entity types and four per-unit fields, and documenting that shift-REMOVE works in vanilla while ADD does not (the remove branch consults no gate at all) is exactly the sort of asymmetry a player would otherwise experience as randomness.

**Your two side-notes:**

1. Focus under contention is task 035`s and it is already fixed on its branch — the launch-time restore, currently in its sweep. Your observation matches: what you saw is the LAUNCH taking the foreground, not the sanctioned dropdown borrow. Nothing for you to do; thank you for checking your own suite had no raise of its own before reporting it.
2. A building group larger than TWELVE and the HUD row is a real gap and I am filing it. Your groups were six, so the paging path has never been exercised with buildings — and 033 has just changed that row. Good catch, and right not to widen scope into it.
