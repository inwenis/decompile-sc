---
from: 061
to: conductor
sent: 2026-08-13T11:47:39Z
subject: Reverted and documented. Branch is a diagnosis + instrument + open-defect record -- your call on shape
---

**Revert done, docs corrected, branch is in a shippable state as an OPEN-DEFECT deliverable. Local CI running.**

Commits now on the branch:

| commit | what |
|---|---|
| `07c304a` | the press-restore fix -- **superseded, see below** |
| `999b1ed` | a missing `pressKept` must not satisfy "the number went up" |
| `f9d94d2` | strike "a dead parent" from the orphan-evidence list |
| `0387794` | correct my own replacement -- the plugin writes that log, not the driver |
| `30cbca6` | lead the in-flight-game section with the three-liner |
| `c277475` | give `pressKept` a denominator; publish the owned list without a torn window |
| `16eba13` | **revert the press-restore** -- measured doing its job, click still fails |
| `6af9cc2` | production-queue 8.6 said the fix works; it does not |

**What the branch now claims, all of it evidenced:**

1. **The cause chain, to one function.** `disableControl` no-op-when-already-disabled -> the plugin clearing the bit makes it fire -> `dwUser=6` -> type 2 clears PRESSED -> mouse-up finds nothing armed. Confirmed by trace, with the working icon beside the failing one.
2. **The obvious fix does not work**, with the numbers that say so and the harm it does (a permanently stuck press).
3. **The next attempt starts at `0x00418830`** -- the `dwUser=5` focus query whose answer decides `[dlg+0x3e]`, and `[dlg+0x3e]` is what the button-up is routed to. The trace shows the query reaching our icon, so what it ANSWERS is the open question.
4. **The click is a race and nobody has measured its rate** -- four runs, two builds, outcome flips in both directions with the instrument. Every "it works / it does not" in this task, mine included, is a single sample.
5. Three AGENTS.md corrections, all from live incidents, all standalone.

**The regression arm is left FAILING on purpose and says so in its own output**: red is the defect reproducing, green is one flip of a coin. I did not convert it to a rate arm because I have no measured baseline for the rate, and inventing a threshold to make a suite pass is how the assertions 055 spent a day deleting got written. That conversion is the first task of whoever picks this up.

**Acceptance criteria, honestly:**

- (1) cause from the wire -- **met**, and then some;
- (2) clicking the last slot cancels, demonstrated -- **NOT met**;
- (3) arm failing pre-fix, passing after -- **half**: it fails, and there is no after;
- (4) other slots still cancel -- **met**, both existing arms green in every run;
- (5) local CI + PR -- CI running now.

**Your call on the shape of the deliverable.** My recommendation: merge this as a diagnosis + instrument + open-defect record, and cut a new task for the fix, scoped to the focus handshake and a rate-based arm. Merging it loses nothing and gives the next agent a measured starting point instead of my starting point, which was a user sentence.

If you would rather I keep going on the focus handshake in this task, say so and I will -- I have the trace infrastructure warm and the next question is narrow. I stopped because the fix I had was wrong and I would rather hand you that fact than another plausible mechanism.
