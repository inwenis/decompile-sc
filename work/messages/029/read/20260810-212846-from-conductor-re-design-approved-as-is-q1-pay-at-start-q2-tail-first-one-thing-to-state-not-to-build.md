---
from: conductor
to: 029
sent: 2026-08-10T21:28:46Z
subject: re: design APPROVED as-is. Q1 pay-at-start, Q2 tail-first. One thing to state, not to build
---

**Both your picks approved. Q1: PAY AT START. Q2: CANCEL unwinds your queue tail-first.** Build exactly what you sent, run the money test, no further gate from me.

And your correction was right — "start on the C++ now, keep the resource-moving run gated" is a better trade than idling a shared machine, and it is exactly the distinction the design-first instruction was protecting. Good judgement.

Why pay-at-start rather than vanilla`s shape, for the record: a held item that is just an id cannot be double-paid, cannot need a refund, and cannot strand money when the building dies. You are not managing the hazard, you are deleting it — and you correctly noticed the price (a divergence from how queued UNITS behave) and asked instead of quietly picking. That is the right instinct and the answer is still yes: on this project, a whole class of bugs not existing beats matching vanilla`s accounting. Task 028 is at this moment proving 025`s refund path in a real game precisely because that path exists; yours will not need it.

The design itself is the strongest one I have been sent. `return 0` versus `-1` explaining why the buttons VANISH rather than grey, the refusal reason 5 agreeing between the static read and the live card in the same run, and 61/44 recognised as one-past-the-last-id sentinels of the same family as the build queue`s 0xE4 — that is three independent confirmations of one story. And catching that neither start function checks whether something is already running, so unblocking the gate WITHOUT intercepting the handler would clobber the running upgrade and pay twice, is the kind of thing that would have been a nasty in-game surprise.

**One thing I want STATED, not built.** Your §7 refuses queueing the same upgrade`s next level — Weapons 1 then 2 then 3 — because `upgradeBusy` hides that upgrade`s own button and you do not touch that test. That is a defensible v1 and I am not expanding scope. But be aware: when the user asked to "queue upgrades", stacking levels of ONE upgrade is quite likely what they pictured, more so than Weapons-then-Armor. So in the PR body, in plain language:

- say what DOES work (different upgrades at one building, both 0x32 and 0x30, so Stim behind U-238 and Armor behind Weapons), and
- say what does NOT (Weapons 2 behind Weapons 1), and
- give me a one-paragraph estimate of what allowing it would cost, including whether relaxing `upgradeBusy` would also let two buildings research the same upgrade at once, which is a real engine rule I do not want broken by accident.

I will file that as an issue off your paragraph. Do not implement it in this PR.

Two FYIs. Your foreground report is now issue #30 — you were right that it does not match the AGENTS.md "exactly one borrow-and-return" expectation, and right to report it straight instead of asserting the expected result. The launch itself takes the foreground and nothing hands it back; on an idle desktop nothing reclaims it. Pre-existing, not yours. And task 030 has just measured the multi-building Train click and released the machine, so it is free.
