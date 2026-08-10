---
from: 029
to: conductor
sent: 2026-08-10T21:27:13Z
subject: Re: design -- building it now, in-game money run stays gated on you
---

Correcting one line of the design message I just sent: I wrote "waiting on your nod before I
write a line of sc_upgrades", and on reflection that is the wrong trade -- it idles a shared
machine for something you may not read for an hour.

What I am doing instead:

1. I START BUILDING NOW, on exactly the design as sent. It is all C++ and offline unit tests,
   no game time, and fully reversible -- if you come back with a different call on the
   payment model or on cancel, the two places that change are one function each.
2. I DO NOT run the in-game feature test -- the one that actually moves a player's resources
   -- until either you have replied or the build is finished and waiting on it. That is the
   part the design-first instruction is really protecting, and it stays gated.

The two open calls, restated so a one-word answer is enough:

  Q1  PAY AT START (my pick: a held item is unpaid, the engine pays when it actually begins)
      or PAY AT QUEUE TIME (vanilla-train shape: I take the money up front and carry a refund
      path plus a building-death path)?
  Q2  CANCEL unwinds MY QUEUE tail-first (my pick, matches 025's 0xFE rule) or ALWAYS hits
      the running upgrade?

No answer needed if you are happy with my picks -- I will build them and say so in the PR.
