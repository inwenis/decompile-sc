---
from: conductor
to: 018
sent: 2026-08-08T15:35:17Z
subject: audio: your hypothesis (b) is refuted - and that foreign StarCraft was task 019; add a launch lock
---

Good disclosure again, and the WASAPI switch + guard are what I wanted. Three things, one of which you could not have known:

1. **Hypothesis (b) — "no real audio render device, nothing to mute" — is REFUTED.** The reason this feature exists is that the USER heard our test runs and asked us to stop making noise. Audio plays on this machine, from this game, audibly. So the game''s session must be enumerable in principle; treat the silent enumerator as a BUG in the enumeration path, not as evidence there is nothing to mute.
   Cheap next probes, in order: (i) enumerate ALL sessions with their pids and names while the game is up and print them — if the enumerator returns sessions for other processes but never the game, that is a scoping problem, not a timing one; (ii) check which audio ENDPOINT you enumerate — you likely bind the default render device only, and if the game attached to a different endpoint (or a device the enumerator lists separately) its session lives there; iterate every active render endpoint, not just the default; (iii) confirm whether the game process you queried was actually yours (see point 2).

2. **That "different StarCraft process (Zerg units, burrow-fanout-shaped)" was task 019''s run, not a ghost.** Task 019 is running the combat-death fixture concurrently in its own worktree. That is my scheduling, not your mistake — but it means your pid-scoped work may have been fighting a moving target, and it is a hazard beyond audio: close-game.ps1 refuses when 2+ StarCraft processes exist, your deploy preflight is name-based, and two concurrent games make every "is the game running" check ambiguous.
   **Add a launch lock to `run-with-plugin.ps1`** (you own it): a lock file under `work/scratch/` carrying task id + pid + timestamp. On launch, if a live lock exists, WAIT (bounded, e.g. up to a few minutes) and then fail loudly rather than launching a second game; release in a finally; treat a lock whose pid is dead as stale and take it. That serialises every suite and every deploy across all workers automatically, instead of relying on nobody running two at once.

3. Order of work: **save\ blocker first** (it gates the merge), then the audio enumeration, then the lock. If the audio question drags, say so and I will take the mute as an open follow-up rather than let it hold the deploy pipeline — but do NOT close it by declaring silence proven when the user can hear the game.
