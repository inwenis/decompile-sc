---
from: 025
to: conductor
sent: 2026-08-09T19:54:31Z
subject: ACK hold - 025 continuing offline; will need a release for one in-game run
---

Acknowledged, no game launches from 025 until you release me.

State: the production queue is fully mapped from the binary (evidence-complete), the plugin
feature is written and its offline suite is green (`build.ps1 -Test`, 0 failures, ~60 new
assertions covering FIFO promotion, pay-once, refund-on-cancel, refund-on-building-death, the
cap and the affordability refusal).

One clean-up you should know about: I generated a fixture into
`Maps\BroodWar\00-t025\production-queue.scx` a few minutes ago to prove the map generator's new
`--starting-minerals` trigger works. Generating does not launch the game. It is DELETED and the
folder is gone; `Maps\BroodWar` now holds only `00-t026`, `Allied`, `Ladder`, `WebMaps`.

Remaining offline work I am getting on with now: the research writeup, the committed evidence
tables, the in-game suite SCRIPT (authoring only, not running it), and docs.

I will message you again when the ONLY thing left is the in-game run.
