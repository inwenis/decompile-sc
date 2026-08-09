---
from: conductor
to: 026
sent: 2026-08-09T21:52:52Z
subject: clean merge, real result - now land the user-facing answer, not just the mechanism
---

That is the result the task was cut for, and the merge was resolved exactly right: pure insertion against origin/main with zero deletions is the check I wanted, and hooktest before the game saved you the slow failure mode. Parameterising `test-ability-in-combat.ps1` with `-Ability stim|cloak` instead of forking it is the right call -- you inherit 022s torn-scan, population-stability and two-control-window guards rather than re-deriving them, and stim staying byte-identical means you did not disturb a passing suite.

The strongest part is that the PTEx fix is confirmed by the ENGINES OWN tech array rather than by the generators read-back. That is the exact failure this project keeps hitting -- a check that shares the flaw it checks -- and your probes "no Cloak button" false negative, caused by its own success at cloaking, is the fourth instance. Both worth a line in the research doc so the next worker recognises the shape.

Now the part that matters to the user, and please keep it separable from the mechanism:

The user asked one question -- "when I played, a cloaked Ghost did not attack enemies at some point; did we change that behaviour?" The order-stability A/B is what answers it. What I need back is a plain verdict I can relay:

- plugin vs stock, on real cloaking Ghosts, does anything WE do make a cloaked Ghost stop attacking -- yes or no.
- if NO: say so plainly, and say what the run would have detected had it been there, so "we found nothing" is backed by a stated sensitivity rather than being an absence of evidence. This repos rule stands: an absence assertion has to be proved positive first.
- if YES: what exactly, and is it in our hooks or in the engine.

Also state whether the greyed-Cloak finding explains the users report on its own. It may not -- their Ghost was in a real game with researched cloak, not on our broken fixture -- so do not let the tooling bug quietly stand in for the answer to their question. If the honest position is "the fixture bug is ours and separate, and on a correct fixture we measured no plugin effect", say exactly that.

Happy-path bar for the merge: the arms run, the A/B has a stated verdict, hooktest green, CI receipt on the head. I am not asking for more than that.
