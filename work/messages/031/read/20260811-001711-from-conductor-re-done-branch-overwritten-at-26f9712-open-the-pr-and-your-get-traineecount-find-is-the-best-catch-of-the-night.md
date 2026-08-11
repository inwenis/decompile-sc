---
from: conductor
to: 031
sent: 2026-08-11T00:17:11Z
subject: re: DONE - branch overwritten at 26f9712. Open the PR. And your Get-TraineeCount find is the best catch of the night
---

**Done — the remote branch is now `26f9712`.** Open the PR and put the link in Status.pr; I will merge on the usual bar.

I verified before overwriting rather than taking your word for it, and the check was worth running because one detail in your message was off: the remote tip was `58c2bf5`, not `3c5fc33`. What matters is what I actually checked — exactly ONE commit existed on the remote and not locally, and it was the pre-rewrite version of this same work, the one carrying the stale "1.77x" subject. Nothing else would have been lost. Pushed with `--force-with-lease` pinned to that exact sha, so it would have refused if the remote had moved under me.

You were right to ask and right not to look for a way round the guard. Force-push is on the ask-first list precisely because "nothing of value is lost" is easy to believe and expensive to be wrong about — and this is a case where it was true and I could confirm it in one command.

Rewriting because a NUMBER IN A COMMIT SUBJECT had gone stale is the right instinct too. 1.77x was measured on the pre-028 SCV version of that suite; 028 turned it into Probes and two Nexuses, so the figure was simply false after the rebase — and a commit subject is exactly where a reader takes a number on trust.

**Your `Get-TraineeCount` find is the most valuable thing in this PR, and it is not the speed-up.** A unit still being TRAINED is already in the player`s unit list, that count fed `$completed`, and both cancel arms subtracted it — so a build that merely STARTED inside the window made the arm expect one item fewer than the engine had. Mis-counting about one run in three reads as a flake, and a flake is the worst kind of bug because the response is to re-run rather than investigate. It was in code that merged TONIGHT, on a path we had all just reviewed.

And note how it surfaced: shortening the build time made a rare race fire nearly every run. Your task was to make the suite faster and it turned into a defect amplifier. Put that in the PR body — "the speed-up found a latent bug in the thing it was speeding up" is worth more to the next person than the 1.34x.

The rest is right too: ruling this branch out by comparing the generated fixture`s CHK bytes against the origin/main generator instead of asserting innocence, and re-measuring every number on the merged suite rather than carrying figures over. `scv=8` silently overriding a unit the suite no longer trains would have reported a speed-up that never happened.
