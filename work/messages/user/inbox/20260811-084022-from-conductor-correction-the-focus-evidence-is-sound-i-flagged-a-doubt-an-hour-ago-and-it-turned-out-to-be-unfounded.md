---
from: conductor
to: user
sent: 2026-08-11T08:40:22Z
subject: correction: the focus evidence is SOUND. I flagged a doubt an hour ago and it turned out to be unfounded
---

# Correcting myself, because I raised the doubt with you

An hour ago I told you a measuring tool might have been producing traces naming game processes that never existed — and that if it had, conclusions I had already given you as settled might need retracting.

**It was a false alarm, and nothing needs retracting.** The worker who raised it chased it properly: ran both versions of the sampler through a single launch and compared them line by line. Same window handle, same process id, same second. The tool is sound.

What its odd traces were actually showing is a real thing, just not what it assumed: **another worker`s game**. The game is single-instance, several workers share this machine, so a competing launch appears and dies within seconds — a real window, a real process, simply not the one it was measuring. It had assumed the StarCraft in its trace was its own.

So the widescreen focus measurement stands, the earlier multi-process observation stands, and everything I have told you about focus behaviour remains accurate. The worker corrected the rulebook itself and recorded the correction in a commit that says so, rather than quietly editing the mistake away.

I would rather flag a doubt and then withdraw it than let a shaky conclusion stand — but you should know the flag was mine and it was wrong.

# Meanwhile the focus fix got better

The launch focus-steal is now measured end to end:

- Before: the game held your screen for **28.2 seconds of a 28-second run** — effectively all of it.
- First fix: 6.6s.
- Now: **4.3s**, then it hands the screen back to the exact window you were using.

I asked whether the remaining 4.3s was real or just a lazy timer. It is mostly real: about 4.1s is the injector blocking while the game settles, during which none of our code is running. The rest was a needless wait and has been removed.

So the honest description is: **about four seconds at launch, then it lets go.** The floor is injection timing, not something we are choosing, and I have told the worker not to chase it further — it would mean touching the injection path for a launch-time flicker.

Two issues left: the test suite that always fails, and reading the game type from memory.
