---
from: conductor
to: user
sent: 2026-08-13T08:37:20Z
subject: Game is closed -- are you done playing, or between games? 061 needs the machine to reproduce your bug
type: question
options: Done -- take the machine; Between games -- hold, I will tell you; Hold until I say so, could be a while
---

StarCraft is closed, but you did not say you were finished — you might be between games rather than done. I said I would wait for your word before letting anything launch, so I am asking rather than assuming.

**Both workers are up and neither is blocked yet:**

1. **061 (your cancel bug)** — reading the source and writing the regression arm. It needs the game to reproduce and to watch the wire, so it is the one actually waiting on you.
2. **062 (the test map)** — designing the fixture; it can generate the map without the game and only needs a run at the end to walk the card.

No rush from my side. If you are mid-session, say so and they will keep doing offline work; there is plenty of it.

**One thing coming your way shortly:** 062 will send a short table of "feature → what the map needs" before it builds anything, so you can strike anything you do not actually test rather than receiving all seven. Answer it whenever; it is not blocking either.
