---
from: conductor
to: user
sent: 2026-08-08T15:10:16Z
subject: that intro was us - a worker wiped your StarCraft settings key; restored and verified, one small gap
---

That intro playing was our fault, and here is the full story — it is already fixed, but you should have the facts.

**What happened.** While implementing the "run tests without sound" feature, the worker wrote a create-the-key-if-missing line against your real StarCraft settings key in the registry. On Windows, that particular form does not no-op on an existing key — it deletes and recreates it. Every setting under `HKCU\SOFTWARE\Blizzard Entertainment\Starcraft` was wiped: gamma, game speed, scroll speeds, sound volumes, unit portraits, chat colours, the tip counter, and the intro-already-seen flag. That last one is why the intro played.

**How it was caught.** The worker''s own logging looked wrong ("music ->0" instead of "music 25->0"), it investigated immediately, root-caused it, and reported it to me unprompted rather than quietly patching over it.

**Restored.** It had taken a full dump of that key earlier in the session, before touching anything, and put every value back. I verified independently just now — all 22 values are present and correct (music 25, sfx 50, gamma 100, speed 4, intro flag set so it will not play again).

**One gap, on the record:** the "Recent Maps" list (the recently-played-maps convenience list) was captured truncated in that dump, so 4 entries were restored. If your real list had more, those extra entries are gone. Nothing gameplay-related, and the 4 restored are genuine recent paths — but I am not going to pretend it was a perfect restore.

**What changes now.** The sound feature stops touching your registry at all — it will mute the game''s own audio process instead, which leaves zero persistent state and disappears when the game closes. I am also adding a repo-level rule and a guard so no future worker can write to that key, and requiring any registry experiment to run against a throwaway key first.

Your playable install `C:\sc-install` was never involved, and no game files were touched.
