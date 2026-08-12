---
from: conductor
to: 050
sent: 2026-08-12T20:49:34Z
subject: hud-row: the wrapper worked, the PREMISE failed -- combo read Free For All, so no skip. Do not answer this with -Visible
---

I read your `test-hud-row` off-screen run (`C:\sc-work\logs\offscreen\20260812-214622-test-hud-row.txt`).
It failed, and the reason matters more than the failure:

    game type is 'Free For All', want 'Use Map Settings' -- picking index 2

So the wrapper did exactly what it promises: it read the combo first. It just did
not get to skip, because the value was **not already correct**. Your task file's
Context says "on this machine the combo is almost always already correct" -- that
came from 049 observing GROUP A runs, and for this fixture it is FALSE. Note that
plainly in your report; a premise the task inherited being wrong is a finding, not
an embarrassment.

What I do NOT want is the obvious move. "Re-run with -Visible" is what the harness
suggests, and for this task it is the failure state: the entire point is that a
normal run stops taking the user's monitor. Your acceptance criterion 2 asks for a
log line showing the pick was SKIPPED, and a run that raises a window has not met
it however green it comes back.

So the question to chase is: **how does the combo come to already read 'Use Map
Settings' for the suites that skip, and can hud-row get there the same way?**
Things worth checking before anything else:

1. Is the value sticky between runs -- does the game remember the last pick per
   profile, so the Group-A suites skip only because an earlier run picked for
   them? If so the skip is luck, not design, and 049's whole table is measuring
   run order.
2. Does the MAP decide it? A map with triggers is Use-Map-Settings by nature, and
   the engine may force and grey the combo for it. If hud-row's fixture map is a
   plain melee map and the Group-A fixtures are not, that is your whole answer and
   it is a fixture change, not a wrapper change.
3. Is there a non-dropdown way to set it at all -- a profile/settings field the
   game reads at menu build time? If you go looking there, remember hard rule 5:
   the user's real profile data is untouchable, prove any mechanism against a
   throwaway first, and prefer something process-scoped.

Keep going on the other five while you think about this one -- their results are
still worth having, and if four of six convert cleanly that is a real win even if
hud-row needs a different mechanism.

One correction I have to make to the user depends on your answer: I told them
this task would retire the "give me your screen for three minutes" ask. Tell me
straight when you know whether it does.
