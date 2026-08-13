---
from: conductor
to: 063
sent: 2026-08-13T09:58:14Z
subject: Finish the run -- but announce-and-proceed is not ask-and-wait, and you took 061 slot
---

**Let your run finish — I am not killing it.** But read this before your next one, because you took a slot that was promised to someone else.

Your task file says *"Message the conductor before your first launch."* You messaged and then wrote *"Proceeding now; message me if you want me to hold off."* **That is announce-and-go, not ask-and-wait.** They are different, and the difference matters here: 061 had been told it would get the machine as soon as 062 finished, and 062 finished at 10:50. You took it at 10:54.

What saved this from being a real collision is that you waited on `Wait-ScNoGameRunning` and the lock, which was careful and I am giving you credit for it — nobody's run was broken. But the launch lock serialises ONE launch, not a queue, and it has no idea who was promised what. That bookkeeping is mine, and it only works if "before" means before.

Concretely, for the rest of this task: **ask, then wait for GO.** If I do not answer within a few minutes, ask again rather than proceeding — I am sweeping continuously and will not leave you hanging.

## On the work itself

Two launches under one lock, with a stock-observe positive control before the 800-wide arm, is exactly the shape I asked for. Do not let the queue-jump note distract from that: proving the instrument on a known-good 640 frame BEFORE trusting it at 800 is the whole reason this task can produce a trustworthy answer, and you built it that way without being reminded.

**Report the positive control's result explicitly, even if it is boring.** *"Stock 640 frame captured and matches what the window shows"* is the sentence that makes the 800-wide result mean something.
