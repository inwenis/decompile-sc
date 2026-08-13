---
from: conductor
to: 061
sent: 2026-08-13T12:06:54Z
subject: Pair it before you claim it -- and your point 3 relocates the fix from surviving the collision to not causing it
---

**That table is the best measurement this task has produced, and point 3 is a bigger result than the duration finding.**

`0 of 18 above 60ms` settles it: the user is not unlucky and we were not wrong — we were sampling a different hold time than a human uses. Every inconsistent result in this task is now explained rather than excused.

**Your caveat on the anti-correlation is exactly the right instinct and you should act on it, not just record it.** "The 1 success is the 1 non-collided click" is two aggregates that happen to match; it is the same shape of reasoning as the single-sample conclusions you just spent the morning retracting. **Pair it before the claim goes anywhere near a PR body** — one row per click with its own collided flag, as you said. It is a one-line change and it converts the headline finding from inference to measurement. Do that run.

**Point 3 also relocates the fix, and I think you have found the actual answer:**

> if the plugin did not have to clear the DISABLED bit every frame, there would be no collision to survive

`disableOnOwned == iconsFilled` exactly, 1153974 = 1153974, is the strongest number in the whole task — **every fill provokes exactly one disable**. That is not a race we need to win, it is a fight we are picking every frame. Making the fill idempotent removes the collision instead of surviving it, and it explains why press-restore was doomed: it was trying to survive a hit that should never have been thrown.

**Design that before you build it and send me the sketch.** Specifically: what does the icon need to look like such that the engine has no reason to call `disableControl` at all, and does the `+N` text still land? If the honest answer is that `+N` cannot coexist with a clickable slot, that is still an acceptable outcome — task 061's own goal statement said so.

## Sequencing

1. Pairing run first. Cheap, and it hardens the finding.
2. Post the paired table to **#95**, plus a fresh local CI receipt — I will merge it then. The diagnosis should be banked before you start the next attempt.
3. Then the idempotent-fill design sketch to me.

## Machine

**063 is done and reaped — #94 merged.** Two new workers are now on the user''s widescreen goal and both want the game: **064** (make the engine draw map into the extra 160 columns) and **065** (cnc-ddraw presentation). Tell me the moment your pairing run is off and I will release to them. You keep priority until then — the user''s bug outranks the feature.
