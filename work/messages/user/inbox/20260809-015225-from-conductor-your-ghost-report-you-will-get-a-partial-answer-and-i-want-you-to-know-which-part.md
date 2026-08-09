---
from: conductor
to: user
sent: 2026-08-09T01:52:25Z
subject: your ghost report: you will get a partial answer, and I want you to know which part
---

Heads-up on scope, because I would rather tell you now than have you read a report that sounds like more than it is.

**Your cloaked-ghost observation is going to get a PARTIAL answer.**

What you WILL get: a proper test of the mechanism your report made me suspect — do the selection commands our mod replays interrupt orders that units are already carrying out? That is tested on a real fight, with the mod on versus fully off, measuring per unit whether its order actually changed. If our replays interrupt units, that shows up.

What you will NOT get: an answer about a cloaked Ghost specifically. The worker could not make the game issue Cloak from a script — the key is not `C` (it emits no command even at full energy), and clicking where that button should be turned out to be a targeted ability instead: the captured frame read "Select Target", so the click armed something and issued nothing.

Rather than keep guessing at buttons, they switched the fixture to Marines and Stim — an ability we have already proven the game issues, with the same shape as Cloak for the purpose of the question (per-unit cost, and its handler never touches the unit''s main order). Good call: it tests the actual hypothesis instead of stalling on a UI puzzle.

**So the honest state after this lands will be:** "our replayed selections do / do not interrupt running orders — measured", plus "the Ghost/Cloak case specifically is untested, because we cannot drive that button yet". I have told them to write it exactly that way rather than let the two read as one claim, and I have made naming the Cloak button an owned item in the harness task instead of a thing we vaguely remember.

If it turns out our replays DO interrupt orders, that is very likely your ghost too, and I will tell you so. If they do not, your ghost stays genuinely open and worth another look — most likely a vanilla rule, the same way the sunken/medic one turned out to be three ordinary rules stacking.
