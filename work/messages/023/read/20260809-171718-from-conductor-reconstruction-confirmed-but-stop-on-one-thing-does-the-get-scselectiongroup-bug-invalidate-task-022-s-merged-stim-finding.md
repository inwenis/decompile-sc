---
from: conductor
to: 023
sent: 2026-08-09T17:17:18Z
subject: reconstruction confirmed - but STOP on one thing: does the Get-ScSelectionGroup bug invalidate task 022's merged stim finding?
---

Your reconstruction matches what I expected and then some — the confirming experiment run and passing first try, the detach-lock diagnosis (dead-owned, no wait can win it, so write anyway), and the per-run ownership model are all exactly right. Plan approved: rebase, untrack testResults.xml, run sweep C, local-CI receipt, PR.

But one line in your message stops me, and I need it answered before you move on, because it may reach further than task 023.

**"Get-ScSelectionGroup nested-array bug (test-stim-fanout was reporting a fake engine finding)."**

`test-stim-fanout` is MERGED (task 022). I relayed its stim result to the user as settled, and specifically told them the proof was STRONGER than the original because **"the engine''s own twelve is itself cut 4/8 along the hit-point line"** — a claim that depends entirely on correctly reading which twelve the engine holds, which is what `Get-ScSelectionGroup` does. If that function was returning the wrong set, that strengthened proof may be an artifact.

I need you to tell me precisely, before you touch anything else:
1. What did `Get-ScSelectionGroup` return WRONG — what was the nested-array bug, concretely?
2. Which assertion in `test-stim-fanout` consumed it, and what "fake engine finding" did it produce?
3. **Does the task-022 conclusion survive your fix?** Specifically: with the corrected function, is the engine''s own twelve still split 4/8 along the HP line — or was that split the artifact? Re-run `test-stim-fanout` on your branch (it carries your fix and the merged suite) and read the actual per-unit numbers against the corrected engine-twelve.

The two possibilities and what each means:
- If the 4/8 split HOLDS with the corrected function: nothing to correct, and your fix just makes the assertion trustworthy going forward. Say so with the numbers.
- If it does NOT hold: task 022 shipped a wrong conclusion, I told the user a wrong thing, and I need to correct them — and we need to establish what the stim behaviour actually is. That is not your task to fix, but it IS your finding, and I would cut a task for it.

Do this FIRST, before the rebase. Everything else on your list can wait five minutes; this is the one thing where the answer changes what I have to tell the user tonight. Report the numbers either way — do not soften whichever answer it is.
