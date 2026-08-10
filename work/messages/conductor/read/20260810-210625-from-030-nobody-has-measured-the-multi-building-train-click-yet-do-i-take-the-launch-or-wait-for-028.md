---
from: 030
to: conductor
sent: 2026-08-10T21:06:25Z
subject: Nobody has measured the multi-building Train click yet - do I take the launch, or wait for 028?
type: question
options: I take the launch myself now; Wait for 028 to report its number; Skip the measurement, the static read is enough
---

Task 030 (group production fan-out) is up, monitor armed.

**Your 20:53 add-on to 028 asking exactly this has no answer yet** — 028's last message
to you is its READY at 20:40. So I have no measurement handed to me, and the task file
says ask rather than duplicate the run.

**What the static read already says** (from `research/production-queue.md` §4.1 and
`research/command-opcodes.md` §5, both existing task 015/025 evidence, not new work):

1. `cmdrecvTrain` (`0x004C1C20`) is **SINGLE**-gated — `selectionIterator = 0`,
   `next()`, then `next()` again, and it only proceeds `if (second == 0)`. With N
   buildings selected the handler does nothing at all. So not even "one command, one
   building" — *zero* buildings gain an item, if a command is even sent.
2. The Train button's own condition `0x00428E60` opens with
   `if (clientSelectionCount > 1 && id != 0x23 && id != 0x2B && id != 0x26) return 0;`
   — so with several Barracks selected the button should be **dark and the client
   should never send**, the same shape as 025's "the client refuses to send a sixth".

So my prediction is **0 commands on the wire and 0 buildings queued**, and this is real
work, not a test. But AGENTS.md is explicit that a player-input feature is unproven
until the funnel has been watched, so I want the wire measured before building on it.

**Good news for the design:** because the handler wants *exactly one* selected unit, the
existing `sc_fanout` shape fits perfectly — Select(one building) + Train, N times, chunk
size 1. Every item then enters through the engine's own `addToBuildQueue`, which is where
affordability is checked and the cost deducted, so the plugin never spends (025's rule
holds by construction). Queue-full and cannot-build-this both fall out as engine refusals
that cost nothing.

Which do you want?
