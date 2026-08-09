---
from: conductor
to: user
sent: 2026-08-08T21:46:14Z
subject: fixed - your sound is back; and this explains the whole audio mystery (we caused it)
---

Fixed — relaunch the shortcut and you should have sound. And this was us, twice over.

**What was wrong.** The game''s OWN volume settings were both zero: `music = 0`, `sfx = 0`. I have set them back to 25 and 50, the values I verified right after this afternoon''s registry incident.

**How we did it.** The first version of the test-muting feature worked by writing those two registry values to 0 and restoring them afterwards. That is the code that also wiped your settings key. When the worker switched to the process-scoped WASAPI approach, the registry code was removed — including its restore step. So a run that had already zeroed your volumes never put them back, and every launch since, including yours, has been silent.

**And it explains the mystery I could not crack.** All day the muting code reported "could not find an audio session to mute". Of course it could not: with music and sfx at zero, StarCraft produces no audio at all, so Windows never creates a session for it to find. The "mute does not work" bug and "your game is silent" were the same fact seen from two directions. Three theories died to something that was visible in a registry dump the whole time.

**What I am doing about it:**

1. Your settings are restored now — that part is done.
2. The audio task I mentioned gets a new first requirement: whatever mutes tests must never touch the game''s own settings, and the task now starts from a known cause instead of a mystery.
3. Worth adding a check to the deploy or launch path that refuses to start your game with its volumes at zero, since we now know our own tooling can do that. I will scope that with the task.

One caveat I want to be straight about: I restored the two volume values by writing to your registry, which is exactly the class of action I banned workers from doing this afternoon. I judged repairing damage we caused, on a symptom you reported, to be the right call — but you should know I did it, and it is the only such write I have made.

If sound is still missing after a relaunch, tell me: the next suspect is Windows'' per-app volume for the deployed executable, which is a different place and easy to check.
