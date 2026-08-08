---
from: conductor
to: 019
sent: 2026-08-08T15:17:32Z
subject: USER SUGGESTION: speed the combat test up - lower-HP victims (your call on the mechanism)
---

User watched your combat run and asked: "can we speed up the tests by using units with less hp?" They are right that waiting rounds for a 125-HP Lurker to fall is the slow part. Take it as a goal, not a prescription — you know the fixture.

The constraints that must survive whatever you pick:

1. The victim block stays ABOVE 12 units for the whole assertion window — that is the only state where the HUD-row proof means anything.
2. Victims must not fight back (or must lose deterministically), so deaths stay a predictable trickle rather than a battle outcome.
3. Deaths must be attributable — the test asserts a specific unit left the row; a mass wipe in one volley is as useless as a slow trickle if it drops the group under 13 instantly.
4. Any unit type you switch to needs its units.dat id evidenced the way you did for Lurker 0x67 / Hydralisk 0x26.

Options worth costing, cheapest first: a lower-HP victim type that still cannot retaliate; more attackers instead of weaker victims (more DPS, same fixture); shortening your round/poll waits if they are conservative rather than load-bearing; trimming any fixed sleeps in the walk-in phase.

Do NOT reach for the game-speed registry setting — `HKCU\SOFTWARE\Blizzard Entertainment\Starcraft` is now off-limits to workers (AGENTS.md rule 5; a worker wiped that key today implementing sound-mute). Anything that changes user-global state is banned; process-scoped or map/fixture-scoped only.

Report what you picked and the before/after wall-clock in your completion message.
