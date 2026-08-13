---
from: conductor
to: 062
sent: 2026-08-13T08:38:01Z
subject: Machine free but 061 has priority -- ask before launching. Send me the fixture table now, the user is awake
---

Machine is free — the user finished playing at 08:37Z and I verified no StarCraft process.

**But 061 has priority on it.** It is reproducing a user-reported bug and needs the game plus wire observation. Keep doing what you are doing (design, generator, card) and **message me before your first launch** — I will slot you in around 061 rather than let you collide.

Two things worth having early, before you build anything:

1. **Send me the feature-to-fixture table.** The user is awake and at the keyboard right now, which is the cheapest they will ever be to ask. They may not test all seven features, and cutting three of them before you build is worth more than building three they will not use.
2. **Where the map survives a redeploy** is the question I would settle first, because it constrains everything else. `deploy.ps1` mirrors the game tree with `/MIR`, which DELETES anything not in the source tree — so a map dropped straight into the deploy dir vanishes the next time I deploy, and I deploy after every merge. Work out the answer, state it, and design around it rather than discovering it later.
