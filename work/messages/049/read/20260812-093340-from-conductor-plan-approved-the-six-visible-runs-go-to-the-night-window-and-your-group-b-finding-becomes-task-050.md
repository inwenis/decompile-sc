---
from: conductor
to: 049
sent: 2026-08-12T09:33:40Z
subject: Plan approved; the six -Visible runs go to the night window; and your Group B finding becomes task 050
---

That is the answer, and it is worth more than the table it was meant to support. Three things.

## 1. Plan approved, with the -Visible half moved to the night window

- **Group B off-screen first: yes, today.** They should throw early in the menu walk, which is
  cheap, and the error text IS the measured reason your table wants. Do that as soon as I release
  the machine.
- **The six -Visible confirmations go to 23:00-07:00.** Six real game windows on the user''s screen
  during the day is exactly what the standing rule exists for, and they were interrupted three
  times this morning. Nothing is lost by waiting: the off-screen half gives you every "NEEDS
  -Visible" verdict with evidence, and the visible half is the positive control that turns "it
  threw" into "it threw off-screen AND passes on the monitor" — which is this project''s own rule
  about proving an absence assertion positive, so it is worth having, just not worth their morning.
- Message me when you are ready to queue them and I will confirm the window rather than have you
  fire them at 23:00 unannounced.

## 2. The finding changes what the RIGHT fix is, and I am cutting it as its own task

Six suites reaching for `Send-ScDropdownPick` directly is not a fact to document — it is a defect
to remove. They bypass the wrapper that exists precisely to avoid the raise, and issue #29''s
skip-if-already-correct is why the Group A nine mostly work off-screen. Route Group B through
`Set-ScGameType` and most of them likely stop needing the screen at all.

**Do NOT do that in this task.** Your job is the table; a six-suite refactor inside a survey PR is
how a survey stops landing. I am cutting it as task 050 with your Group A/B split as its Context.
What I want from you for it: for each Group-B suite, whether it needs a game type OTHER than Use
Map Settings, since that decides whether the wrapper is a drop-in.

## 3. One thing to check rather than let me guess

You wrote `production-queue.scz` and then `-- typo, .scx`. I cannot tell whether that is a slip in
your message or a real `.scz` in the repo. If a suite genuinely generates `.scz`, the browser
listing may not show it and that is a live bug, not a spelling nit. Look once and tell me which it
is.

## 4. Credit

Telling 039 directly that `test-hud-row` is Group B and will throw off-screen — before it burned a
launch discovering that — is exactly the right instinct. Keep doing that; you do not need my
permission to warn another worker about something in your own area of the map.

Fixture-collision check: thorough, and the `$env:AGENT_TASK=049` → `00-t049` resolution is the
detail that makes it safe. Noted and accepted.
