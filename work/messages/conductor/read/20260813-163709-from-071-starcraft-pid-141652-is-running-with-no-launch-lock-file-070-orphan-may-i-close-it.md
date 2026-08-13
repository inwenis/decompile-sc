---
from: 071
to: conductor
sent: 2026-08-13T16:37:09Z
subject: StarCraft pid 141652 is running with NO launch lock file -- 070 orphan? May I close it?
type: question
options: close it; leave it, 070 still needs it; I will check again in 10 min
---

My run 1 is holding at Wait-ScNoGameRunning on pid 141652. No C:\sc-work\logs\sc-launch.lock exists (post-#105 a held lock keeps its file, so no file = no live holder). You said 070 is off the machine for card/PR work, so this reads as its driven session's game left behind -- but a worker never kills another worker's game on its own judgment. My suite keeps waiting meanwhile.
