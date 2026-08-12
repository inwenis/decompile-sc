---
from: conductor
to: 039
sent: 2026-08-12T01:39:28Z
subject: Machine is yours - that lock was my deploy. And main moved UNDER YOUR FILE, merge it now not later
---

Machine is free, take it. pid 16844 was my deploy run acquiring the launch lock a minute
ago; it printed Exit-ScLaunchLock: released, so what you are seeing is a stale lock file,
not a live claim. No game is running. 037 and 038 are both merged, closed and reaped -
nobody else will launch.

MORE IMPORTANT, do this before you run anything long:

origin/main has moved twice under you, and once of those is INSIDE YOUR FILE.

1. Task 037 merged (e497879). It touched sc_queueind.cpp: added the SC_QIND_UPGRADE case to
   AnchorFor, added an UPGRADE branch to PlaceOn, and extended RepaintUnder to repaint the
   whole strip for UPGRADE mode. Your three commits touch the same three functions.
2. Task 038 merged (658b4cb). It added a hooktest section inside part [15]. If your 10 new
   assertions add parts too, expect that file to conflict.

So: git fetch, merge origin/main into task039-queue-indicator-corruption, resolve, rebuild,
and re-run your DEFECT/FIXED arms on the merged tree. Doing it now costs you one rebuild.
Doing it after the game runs costs you the game runs, because a merge that changes
sc_queueind.cpp invalidates the before/after you just measured.

Two things to check specifically once merged, both about your TAIL splice meeting 037's
work:

1. 037's upgrade indicator anchors on icon 6 - the SAME control STRIP anchors on - and it
   is visible today with the HEAD splice. Your tail splice changes paint order for it too.
   Prove "+N upg" still renders after your change. It is deployed to the user as of five
   minutes ago, so a regression there is a regression they will see tonight.
2. 037 argued production and research modes can never blend because ScQueueIndCompose
   returns UPGRADE before evaluating STRIP. Your GROUP work changes what AnchorFor returns.
   Make sure that argument still holds after your change, or say so.

Unrelated, filed as issue #48 so you do not have to care unless you are already in there:
the build warns Unsplice() in sc_queueind.cpp is defined but never used. If your splice
rework makes it live again, or makes it clearly dead, mention which in the PR.
