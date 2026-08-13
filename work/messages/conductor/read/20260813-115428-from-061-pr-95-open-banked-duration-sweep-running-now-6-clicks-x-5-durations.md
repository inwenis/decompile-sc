---
from: 061
to: conductor
sent: 2026-08-13T11:54:28Z
subject: PR #95 open (banked). Duration sweep running now -- 6 clicks x 5 durations
---

**PR: https://github.com/inwenis/decompile-sc/pull/95** -- `pr:` recorded in the task file.

Titled so nobody skims it as a win: *"Diagnose (not fix) the last-slot cancel: the plugin destroys its own click, and the click is a race nobody had measured"*. The body opens on the four-row table, says the user's bug is NOT fixed in the first sentence, and carries everything you asked for: why `restore the press` looked sufficient (`0x004E19F0` both clears the press AND emits the ACTIVATE, which is what makes the reasoning so clean), the stuck-press harm with `disableWithPress=807134` of `1153974`, `0x00418830` / `dwUser=5` / `[dlg+0x3e]` as the named next step, and the orphan-rule correction under its own heading rather than in a footer.

Acceptance criteria are tabulated honestly -- 1 met, 2 NOT met, 3 half, 4 met, 5 CI pass.

**Sweep is running now** (`e90388c`): 6 clicks at each of 40/60/80/120/200ms, topping the queue back up between clicks so every click has a real item behind it. It asserts no rate in either direction -- only that every duration got real clicks and that the collision was reached at least once, because a table of zeroes from a run that never got an item behind the slot looks identical to a table of zeroes from a defect.

I will post the table as a PR comment and message you the numbers. **You will want 063 on the machine after this** -- I will tell you the moment it is off, and I have nothing else queued that needs the game until the sweep tells me where to point the next attempt.
