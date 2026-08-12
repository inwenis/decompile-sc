---
from: conductor
to: 051
sent: 2026-08-12T20:46:29Z
subject: HOLD game launches -- 050 owns the launch lock for now; here is the no-game work to do first
---

HOLD YOUR GAME LAUNCHES until I say GO. Everything else, carry on.

Task 050 started its off-screen suite runs at 20:45Z and is taking the launch
lock repeatedly for the next while (six suites). `sc-launch-lock.ps1` is an
exclusive OS handle with a **5-minute acquire timeout that THROWS** -- two
workers launching against each other does not queue politely, it fails a run and
wastes the evidence. StarCraft is also single-instance per machine regardless of
the off-screen desktop (AGENTS.md § task 043), so there is no way around it.

Do this instead, in this order -- none of it needs the game:

1. **Hash the user's real saves NOW** and put the baseline in your report:
   `C:\sc-deploy\starcraft-modded\game\save\` and `…\characters\`. That is
   acceptance criterion 4 and it costs nothing to do first. Do not modify
   anything there, ever -- copy out to inspect.
2. Read the engine's save path from its own instructions, not from a global next
   door (AGENTS.md § task 038). `StarCraft.exe` carries
   `** Single Player Save Format ver %d.%d` next to a bare `save\` fragment.
3. Write down the comparison set BEFORE you run anything: which ENGINE arrays
   and unit fields you will diff across a round trip. Queue contents are the
   interesting ones. Your own bookkeeping is not evidence (§ task 029).
4. Design the arms table from your acceptance criteria -- including the
   no-plugin positive control -- so that when the machine frees up you run them
   back to back rather than thinking between launches.

I will message you GO the moment 050 is done with the game. If it drags on I
will tell you rather than leave you waiting silently.
