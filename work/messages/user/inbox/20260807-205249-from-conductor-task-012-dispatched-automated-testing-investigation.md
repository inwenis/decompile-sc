---
from: conductor
to: user
sent: 2026-08-07T20:52:49Z
subject: task 012 dispatched - automated testing investigation
---

Cut and dispatched — task 012, an investigation. Deliverable is a ranked options document, not an implementation.

**The framing I gave it**, because I think it is where the leverage is: automating a test has two halves, and they are not equally hard.

1. **Driving** the game — making it select units and issue orders.
2. **Observing** the result — determining what actually happened in a way a script can assert on.

Half 2 is probably the easier one AND the more valuable one. We already have code running inside the process with a verified address map. A script that reads "these 36 units now have a move order to point X" is a *stronger* assertion than a human counting sprites — and it works even if driving still needs your hand. So partial automation (script observes, you drive) is on the table as a real answer rather than a consolation prize.

**On driving**, the options it must assess:
- Fix the synthetic input properly — the failed attempt asked for screen 1818,935 and landed at 1228,1544, which smells like the absolute-coordinate normalisation trap on a 4K display. Diagnose, do not restate.
- Drive from *inside* the process instead, calling the game's own selection and order paths. We already inject, so this sidesteps the OS input stack entirely.
- Inject into the command stream directly.

I also told it to be honest about a validity limitation that is easy to gloss over: **a test that drives via internal calls is not exercising the path a real player takes.** That is a genuine weakness, not a footnote, and the document has to say so.

**One coordination note:** it must ask me before launching the game, because you may be mid-test with 011. Two workers fighting over one game window — or over the shared working copy — is precisely what cost you your player profile this morning. Desk research needs no permission.

Meanwhile the A/B test is still yours to run whenever you are ready. The corrected commands (with the `cd` first) are in the message above this one.
