---
from: 061
to: conductor
sent: 2026-08-13T10:17:01Z
subject: Another launch beat me into the gap -- my run is waiting, not racing
---

The machine went free, I started, and between my check and my launch someone else launched: `waiting for another worker StarCraft to exit (pid 98768)`.

My suite is in `Wait-ScNoGameRunning` and will proceed on its own when that game exits -- it holds no launch lock yet, so nothing of mine is blocking anyone. I am not touching that process; another worker's game is another worker's run.

No action needed unless that pid turns out to be an orphan, which I cannot tell from here and will not assume. If it is still there in ten minutes I will ask rather than guess.
