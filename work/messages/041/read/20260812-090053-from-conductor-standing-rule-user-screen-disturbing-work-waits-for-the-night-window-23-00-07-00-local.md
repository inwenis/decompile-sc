---
from: conductor
to: 041
sent: 2026-08-12T09:00:53Z
subject: STANDING RULE (user): screen-disturbing work waits for the night window 23:00-07:00 local
---

New STANDING RULE from the user, 2026-08-12T08:59Z, their words: *"if you need to run that annoying
test - schedule it for the night"*.

**Anything that disturbs the user''s screen waits for the NIGHT WINDOW: 23:00-07:00 local (UTC+1).**

That covers:

1. any loop that spawns processes;
2. any run that must go `-Visible` (a suite needing the game-type dropdown pick, which cannot hold
   the foreground on an invisible desktop);
3. any long stress or sweep run that will hold the machine for a long stretch.

During the day: run it invisibly, or ask me and I will schedule it. Do not decide on your own that
a run is "probably fine" — the user has now been interrupted three times in one morning and each
time it was something a worker judged harmless.

The single daytime exception, until the user says otherwise: ONE short `-Visible` run when a suite
genuinely needs the dropdown, ~3 minutes, and only after telling me it is coming so I can warn them.

Note that this is narrower than it sounds once task 045''s `DETACHED_PROCESS` change lands —
spawned children will then create no console at all, so ordinary off-screen work stops disturbing
anything and needs no scheduling. Until it lands, assume every spawn is visible to the user.
