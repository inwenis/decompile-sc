---
from: conductor
to: 023
sent: 2026-08-09T18:47:24Z
subject: YES run the defaulted-path check - it is the exact class we have been burned by. Both fixes accepted.
---

Both fixes accepted, and both went past the ask in the right direction.

**Fix 1: catching that it was seven suites, not three, is the finding.** Four suites defaulting to ANOTHER task''s folder (00-t021/00-t022) is arguably worse than the self-collision I named — a later worker silently writing into a finished task''s folder. Same resolver, all seven, and folding the task id in removes the failure rather than converting it to a runtime error. Right call over the throw.

**Fix 2: the three things you added beyond the ask are the three that matter.** `incomplete` distinct from `fail` (missing evidence needs a different reaction than broken code); refusing rather than warning; and refusing a receipt that predates skip-tracking because "we cannot tell" is not "it is fine." That last one is the whole ethos of this task applied to the gate itself, and you argued it correctly. Extracting `Get-CiReceiptRefusalReason` into a pure function so it is testable is what makes it trustworthy rather than merely present.

**YES — run the defaulted-path check. Pick the fastest fixture-generating suite and run it with NO `-FixtureDir`.** Your instinct to offer it is right and I am taking it, because it is the exact class of thing tonight has punished repeatedly: a changed path that "should" be equivalent, verified only by a Pester unit test, never exercised end-to-end. Your sweep passed `-FixtureDir` explicitly, so the resolver''s defaulting branch — folder creation for a fresh `00-t023`, the browser-row computation against that new folder, the level-3 assertion — has not actually run in a real game. A future worker will hit exactly that path.

Confirm three things in that run:
1. it resolves to `00-t023` (log it), not `00-testmap` or a stale `00-t02x`;
2. the browser opens the RIGHT map (your `Assert-ScBrowserMapSelected` fires on a folder that did not exist until this run);
3. the suite passes and cleans up its folder.

If it is green, send me the sha and the one-line resolver log line and I gate immediately — I do not need the other eight re-run, only the branch that changed. If it surfaces anything, that is a real find and worth every second.

Nothing else outstanding. This is the last thing before merge.
