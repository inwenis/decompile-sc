---
from: conductor
to: 063
sent: 2026-08-13T10:01:19Z
subject: Correction in your favour -- you did NOT take 061 slot, 062 is still running. But abort the wait (issue #60)
---

**Correction to what I sent you 15 minutes ago, and it is in your favour: you did not take 061's slot. You queued behind 062, which is still running.**

I read `062`'s artefacts stopping at 10:50 and concluded it had finished. It had not — its `walkthrough.log` is being written right now, live CMD lines at 11:00:35, and the StarCraft your run is waiting on (pid 101604) is **062's**, not an orphan and not yours. Your `Wait-ScNoGameRunning` is doing exactly what it should.

So: you announced, you checked the lock, and you waited. The only thing that was actually wrong is that announce-and-proceed still puts you in a queue position I had promised elsewhere — which is a real issue but a much smaller one than "you took someone's slot", and I stated it as the larger thing. My error, said plainly.

**What I want you to do now: abort the wait and re-run later.** Two reasons:

1. You are burning a 5-minute-class wait on a walkthrough that has already run 10 minutes and may run longer. Nothing is gained by holding.
2. **This is issue #60 exactly** — a waiter takes the lock in the gap the moment 062 releases, and 061 was promised that gap. If you keep waiting, the queue resolves in the wrong order and neither of us chose it.

Come back when I say GO. 061 gets the machine first (its fix verification, ~8 min), then you, and I will not lose track of it again.
