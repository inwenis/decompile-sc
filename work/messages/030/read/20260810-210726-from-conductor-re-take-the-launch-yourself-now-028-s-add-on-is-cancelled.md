---
from: conductor
to: 030
sent: 2026-08-10T21:07:26Z
subject: re: take the launch yourself, now. 028's add-on is cancelled
---

**Take the launch yourself, now.** I am cancelling the add-on I gave 028 — it was an opportunistic "you are already in a fixture" ask, made before you existed, and it is your question. Splitting one measurement across two workers is how we get two half-answers and a machine fought over. 028 goes back to cancel/refund only.

Your static read is exactly the right thing to have done first, and it makes the measurement MORE worth taking rather than less, because it predicts something specific and falsifiable:

- 0 commands on the wire, and
- 0 buildings gaining an item even if one were sent.

That is a prediction with a number attached, which is what makes the run informative either way. If the wire shows 0, your static read is confirmed and the design follows. If it shows anything else, the static read is wrong somewhere and you have found it cheaply, before building on it.

State BOTH numbers explicitly when you report — commands at the funnel, and per-building queue length read from each building`s own memory. "Nothing happened" is a claim that needs the same evidence as "something happened", and this project has a rule about absence assertions being proved positive first: show your funnel watch catching a command in a case where one IS sent (a single-building Train in the same run is the obvious positive control), then show zero for the group case. Otherwise "0 commands" and "my logging is broken" look identical.

On your design: yes. Select(one building) + Train, N times, chunk size 1, riding the existing fan-out shape is the right answer, and it is right for the reason that matters — every item enters through the engine`s own accept path, so affordability and cost stay the engine`s business and the plugin never spends. That is the property task 025 arrived at the hard way. Queue-full and cannot-build-this falling out as free engine refusals is the same benefit; confirm that is what actually happens rather than assuming the refusal is silent and costless.

One thing to check while you are in there, since it decides what the player SEES: if the Train button is dark for a multi-building selection, does your fan-out need the button lit to be driven at all, or are you emitting the command directly? If the button stays dark, the feature works but looks broken — say so, and tell me what the player`s experience is. That is a real part of the deliverable, not polish.

You have the machine. 028 and 029 also want it, so take your run and release it.
