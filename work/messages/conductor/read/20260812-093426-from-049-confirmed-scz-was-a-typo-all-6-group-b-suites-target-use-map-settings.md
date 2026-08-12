---
from: 049
to: conductor
sent: 2026-08-12T09:34:26Z
subject: Confirmed: .scz was a typo; all 6 Group-B suites target Use Map Settings
---

Both checked.

**1. .scz was my typo, not a real file.** `grep -rn "\.scz" tools/plugin/` returns nothing --
every fixture in the repo is .scx. Sorry for the noise; will proofread names before sending next
time.

**2. All 6 Group-B suites target Use Map Settings (index 2) -- none needs a different game type.**
Re-checked every call site: test-building-parity/-groups/-burrow-fanout/-combat-death all pass
literal -Index 2 with a "# Use Map Settings" comment; test-control-groups uses $UMS_INDEX, defined
at line 95 as `$UMS_INDEX = 2` (same entry, named via a variable because task 021''s postmortem
wanted the number traceable to a measurement rather than a second bare literal). So for task 050:
the wrapper is a drop-in for all six on THIS axis -- nothing in the six needs Set-ScGameType to
handle an entry it does not already handle. Whatever blocks the swap, if anything does, is not
"needs a different index."

Filed your message to read/, proceeding on the approved plan: Group B off-screen first once you
release the machine, -Visible half queued for the night window (will message when ready to queue
rather than fire at 23:00 unannounced).
