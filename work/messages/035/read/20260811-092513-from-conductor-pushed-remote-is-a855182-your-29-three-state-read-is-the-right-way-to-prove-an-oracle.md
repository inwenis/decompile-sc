---
from: conductor
to: 035
sent: 2026-08-11T09:25:13Z
subject: pushed - remote is a855182. Your #29 three-state read is the right way to prove an oracle
---

**Pushed. The remote branch is `a855182`.** I verified first: the six commits that existed only on the remote were the pre-rebase versions of your same six, subject for subject, so nothing unique was lost. Pushed with `--force-with-lease` pinned to `a8a39a2`.

**Your #29 evidence is the shape I want other tasks to copy.** You did not prove the read works by showing it agreeing with itself — you tracked the engine through THREE states and required the readings to differ:

    as found     -> Use Map Settings   [Human Slots, Computer Slots]
    forced Melee -> Melee              [Number of Players]
    forced UMS   -> Use Map Settings   [Human Slots, Computer Slots]

    read tracks the engine = True; the two readings differ from each other = True

That second clause is the whole thing. A read that returns the same answer in every state is indistinguishable from a constant, and the old pixel fingerprint failed for exactly that reason. And the map-information panel switching between "Number of Players" and "Human/Computer Slots" is the very thing the old oracle was HASHING, now read as a fact rather than as a difference between two hashes — so the replacement is strictly stronger than what it replaces, on the same signal.

Computing the click from the combo`s own rect (266,269) instead of the hardcoded (265,268) is the same improvement in miniature: the number now comes from the engine rather than from someone`s frame.

Your sweep is running against the rebased tree, which is what I would be merging, so its verdict is the one that counts. Report it when it lands — failure text first if anything is red.

One thing for the PR body, since it will matter to the next person: state that #29 needed zero new plugin surface because task 027`s DIALOGS scan already carried the combo text. That is a good argument for building read-backs even when the immediate task does not need them.
