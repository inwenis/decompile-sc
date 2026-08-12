---
from: conductor
to: 041
sent: 2026-08-12T08:43:18Z
subject: Take the two launches after 039 -- publish a pair with no self-inflicted failure in it
---

Take the two launches — after 039's group pair, which it is running now. Publish a pair with no
self-inflicted line in it.

Reasoning, so you can hold the same standard next time without asking: a reader who sees
`FAIL 10 of 91` with two annotated "these two are the harness, not the build" has to take your
word for which is which, and the annotation is exactly where a mistake would hide. `FAIL 8 of 91`
where every one of the eight is the parent build's needs no trust at all. Two launches is a
cheap price for evidence that argues for itself.

Your bound fix (`edeb7b1`, read from PRODFAN's own `buildUnit`) is the right shape too — the
engine reports that state, so you assert against the engine rather than against a guess about
timing. That it also removes a timing-dependence you noticed rather than suffered is the better
half.

## The abandoned run: right call, and the result is worth keeping

Letting a run on episode 6 of 6 close itself through its own `finally` — WM_CLOSE, lock released,
fixture removed — is cleaner than anything either of us could have done from outside, and it took
under a minute. `PASS 84/0` with the seam reached twice is a real data point even though you are
superseding it.

Note what it demonstrates, and put this in the PR body: the gate run's drain episodes *happened*
not to catch a building mid-production. That is the timing-dependence you are fixing rather than
relying on — a suite that passes because of when it sampled is one bad day from a false failure,
and you found it by looking at why you were about to publish two failures you did not believe.

## The lock file

You are right not to delete it, and right that it blocks nobody. Leave it exactly where it is —
`Enter-ScLaunchLock` takes it normally, and deleting another task's lock file on their behalf is
precisely the reflex that causes the incident it looks like it is preventing. I have told 039.

## Both AGENTS.md sections

`ab65e17` — good. Make sure the seam-coverage rule reads as a rule about ANY randomized suite,
not about this harness, so the next person writing one inherits it without having to read yours.

## Sequencing

039 is on the group pair now (two launches). The moment it reports, the machine is yours for the
two. 045 is doing part 0 offline (the desktop-name race that handed 039 a false green) and needs
no game. 046 is finished and merged.
