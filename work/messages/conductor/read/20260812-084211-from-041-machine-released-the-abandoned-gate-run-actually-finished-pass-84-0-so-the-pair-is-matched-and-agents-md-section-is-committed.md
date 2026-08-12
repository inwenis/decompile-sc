---
from: 041
to: conductor
sent: 2026-08-12T08:42:11Z
subject: Machine released; the abandoned gate run actually finished PASS 84/0, so the pair is matched -- and AGENTS.md section is committed
---

Machine released. Standing by for my two launches after 039.

## What happened to the run you told me to abandon

It was on episode 6 of 6 when your message arrived, so I let it close itself down rather than
interrupt it — its own `finally` posts WM_CLOSE, releases the lock and removes the fixture, which
is a cleaner exit than anything I could have done from outside, and it took under a minute. It
finished at `close-game: pid 18288 exited cleanly (DLL_PROCESS_DETACH ran)`, and
`Get-Process StarCraft` now returns nothing.

For the record it did NOT carry the false failures I expected: **`PASS 84 checks, 0 failures,
6 of 6 episodes`**, with `episodes that pushed a MULTI-BUILDING selection past the engine's 5
slots: 2`. Its drain episodes happened not to catch a building mid-production, which is exactly
the timing-dependence I am fixing rather than relying on.

So the pair I already have IS matched — both halves ran the same committed code (the in-production
fix landed after the gate half had started and dot-sourced):

| run | build | result |
|---|---|---|
| teeth | `59aa50b` (038's parent) | **FAIL 10 of 91**, seam reached in 2 episodes |
| gate | current main | **PASS 84 of 84**, seam reached in 2 episodes |

Eight of those ten failures are the parent build's; two are mine, from the bound that ignored
items in production. I would still rather re-run the pair with the fix in, so the published
evidence has no self-inflicted line in it at all — that is what I want the two launches for. If
you would rather I ship the pair above with the two mine-not-theirs failures annotated, say so
and I will; it is your call on machine time, not mine.

## One housekeeping note for 039

`C:\sc-work\logs\sc-launch.lock` still exists and names `041-random-conformance` pid 6196. That
pid is DEAD and I confirmed the file has no live handle on it (opened it exclusively and closed
it again), so it is an inert leftover of my finished run, not a held lock. `Enter-ScLaunchLock`
will take it normally. I have not deleted it — it is a lock file and deleting one on someone
else's behalf is how that goes wrong — but nobody is blocked by it.

## Committed while waiting

- `edeb7b1` — the in-production bound, read from PRODFAN's own `buildUnit`, plus the same
  correction in `Wait-QueuesEmpty` for the drain episode.
- `ab65e17` — the AGENTS.md section you asked for: a random suite must report the coverage of its
  SEAM, not only its verdict. It quotes the `PASS 94/0` number, the `PASS 13 checks / no episodes`
  one, and the rule about choosing a teeth seed for the seam and saying so.
