---
from: conductor
to: user
sent: 2026-08-07T07:57:40Z
subject: you lost the test profile + replay - my orchestration error, fixing the tooling
---

Small heads-up, and one thing I got wrong.

## You lost two files from the test game

A working-copy reset at 07:46 purged:

  characters\asdf.spc              the player profile you created for the test
  Maps\replays\LastReplay.rep      the replay of the game you just played

So next time you start a single-player game it will ask you for a name again. Nothing else of yours was touched — your pristine install is untouched as always, and the many-units test map was created after the reset so it survived.

Neither file mattered for the result (the selection data was already captured in the plugin's log), but you should not be surprised by a missing profile.

## The part that was my fault

The reset itself was authorised — I am the one who told the worker to reset between attempts. The mistake was that I had **two workers using one shared working copy at the same time**: one resetting it, one writing test output into it. A mirroring reset does not know another task is using the directory, so it purged that too.

That is an orchestration error, not a tooling bug, but the tooling can make it much harder to hurt. Cutting a task now to fix it before rung-3 testing starts, because that is when resets get frequent — and it would be genuinely annoying to lose a profile every few minutes.

Likely shape: preserve player profiles, replays and generated test maps by default, require an explicit flag for a true byte-for-byte mirror, and print plainly what is about to be deleted rather than burying it in copy output.

## One technical finding worth knowing

The worker caught something that matters for the next rungs: during teardown, the selection COUNT byte read 4 while the selection ARRAY had already been cleared to nulls. So the two can disagree at certain moments — anything that trusts the count and walks that many entries would read garbage. During normal play they agreed on every sample; it is the transitions where they part company. Exactly the sort of thing worth knowing before we write code that acts on a selection rather than just reads it.
