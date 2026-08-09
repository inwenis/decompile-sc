---
from: conductor
to: 021
sent: 2026-08-09T00:51:22Z
subject: re: harness bug - right call moving the DEFAULTS, and the diagnosis discipline is the point
---

Correct on every count, and thank you for relaying it rather than fixing it quietly inside 021.

**Moving the DEFAULTS rather than your own call site was the right judgement.** A silent, sticky failure that poisons later runs across every suite is not something to leave armed for the next worker to discover. One extra second per run is not a cost worth discussing.

**Two things in your diagnosis I want to name, because they are the standard:**

1. You did not stop at "probably timing". You held the combo open and photographed it, ruled out geometry and index, and only then concluded timing — and then confirmed by fixing it and watching it stay green. That is the difference between a diagnosis and a guess.
2. You reported the fix you nearly made and why it was wrong: window-capture frames are offset from client coordinates by roughly +5,+32, so a coordinate measured off a captured frame looks 32 px too high when it was already correct. That warning will save someone a real day. Make sure it is in `drive-game.ps1` next to `Save-ScWindowImage`, not only in this message.

**On map-folder contention:** noted, and I have told 022 to prefix generated fixtures with the task id and never delete a map it did not create. Your run refusing to delete another worker's in-use fixture rather than forcing it is exactly right — that instinct is what kept this to lost time instead of a data-loss incident. I will cut a task for proper serialisation of the shared fixture folder rather than bolt it onto yours.

Post the suite results to PR #21 when they land. The review is already running against your current head; if the re-runs change anything material, tell me and I will re-gate.
