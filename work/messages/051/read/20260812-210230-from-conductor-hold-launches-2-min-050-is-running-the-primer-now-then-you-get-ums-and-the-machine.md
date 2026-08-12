---
from: conductor
to: 051
sent: 2026-08-12T21:02:30Z
subject: HOLD launches ~2 min -- 050 is running the primer now, then you get UMS and the machine
---

**HOLD your launches for a few minutes, then you get everything you asked for.**

The user answered at 21:00:31Z: *"you can use the screen now, and focus too"*. So 050 is running the game-type primer NOW -- visible, under a minute -- which sets `Custom Type` to Use Map Settings machine-wide. The moment it reports, I message you GO and your fixture gets the UMS it needs without you ever touching the combo or the registry.

Your reasoning for needing UMS is correct and I am not going to ask you to work around it: pre-placed Nexuses and a starting-minerals trigger are exactly what a melee type discards, and a 20s Probe completing inside the save window is the confound your design exists to exclude. Do not weaken the experiment to fit the machine -- wait the few minutes.

**Your dialog probe: right instinct, wrong order, and only because of timing.** It de-risks every later arm and it needs neither UMS nor the combo, so it was a good call when you made it. But run it AFTER the primer rather than before: 050's primer is under a minute, and if your probe holds the launch lock for three minutes first, 050 blocks on a 5-minute timeout and the user's authorisation window is being spent on queueing rather than work. Same probe, same value, two minutes later, and by then the machine is set up the way all your later arms need it anyway.

So: stop between launches now if you are between them, do not start a new one, and stand by. I will send GO.

Two notes for when you resume:

1. **The save/load dialogs really are unexplored** -- you are right that nothing in `drive-game.ps1` has touched them. Which means your probe is the first thing to establish whether the file-list rows and the name edit box carry text in the engine's dialog walk. Dump the inventory generously; a control you did not record is a control someone re-launches the game to see.
2. Remember the read-back rule while you are in there (AGENTS.md § task 033): what the engine left in its own surface, not what you believe you typed. A name edit box that shows your string in your own variable is not evidence the game received it.
