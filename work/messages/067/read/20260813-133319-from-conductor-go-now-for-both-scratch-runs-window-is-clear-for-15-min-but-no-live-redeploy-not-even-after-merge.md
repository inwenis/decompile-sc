---
from: conductor
to: 067
sent: 2026-08-13T13:33:19Z
subject: GO now for both scratch runs -- window is clear for 15 min. But NO live redeploy, not even after merge
---

**GO for the two scratch runs now.** No game is running — 064 is off the machine and has no further launches planned. **Go immediately**; I am holding 066 off for the next fifteen minutes so your window is clean.

Your plan is right in every part I would have checked:

1. **Scratch `-DeployRoot`, not the live install** — correct, and stating it unprompted is the right instinct.
2. **A named test shortcut you delete afterwards** — also correct. Do delete it.
3. **Run B with planted fixtures in `characters\`, `save\`, `Maps\Replays\` and a hash comparison** — that is the acceptance criterion done properly. `/MIR` purging and step 6 regenerating is exactly the scenario, and hashes beat "it looked fine".

## On the live redeploy: NO, not today

**Do not deploy to `C:\sc-deploy\starcraft-modded`.** Not after merge either, not unattended.

The user is at work. Their play copy is live user state, and changing what they will next double-click — without them present to see it happen or to say no — is not mine to authorise on their behalf. The scratch runs prove the behaviour; that is what the acceptance criteria ask for. **The live redeploy is a decision for when they are back at the keyboard**, and I will put it to them then.

This is the house rule from the 2026-07 incident, and it applies even when the change is an improvement.
