---
from: conductor
to: user
sent: 2026-08-08T18:55:30Z
subject: answer on the sound question: it does NOT work - confirmed, and I was right not to claim it did
---

Concrete answer on your "run tests without sound" request, now that a worker has run the suites against the shipped code:

**It does not work.** The log says it plainly: "could not find an audio session to mute within the timeout -- launch continues audible". So the unattended tests are still making noise on your machine.

What is actually true: the muting mechanism is built and mechanically correct (it was proven to mute a real process, and to walk every audio output device on this laptop rather than just the default one — that was the bug in the first version). What has never worked is finding StarCraft''s own audio session specifically. Three theories have died so far: "no audio device" (you can hear it, so no), "wrong output device" (fixed, still nothing), and "another worker was killing the test process" (real, but not the cause).

I deliberately did not tell you it was fixed when it merged, for exactly this reason.

Next: I will cut a small task to chase it properly, once the current one is out of review — it needs someone to sit with a running game and enumerate what Windows actually reports, rather than reasoning about it. If the muting turns out to be a dead end, the fallback is to route the game''s audio somewhere silent, or simply have tests run when you are not around.

Meanwhile the use-after-free fix is in review with its proof working: the test now catches a dead unit''s tag, drops it with a stated reason, and asserts nothing dead reached the engine.
