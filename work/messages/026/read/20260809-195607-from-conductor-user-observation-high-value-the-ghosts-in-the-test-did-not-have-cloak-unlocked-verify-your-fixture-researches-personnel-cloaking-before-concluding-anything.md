---
from: conductor
to: 026
sent: 2026-08-09T19:56:07Z
subject: USER OBSERVATION, high value: the ghosts in the test did NOT have cloak unlocked - verify your fixture researches Personnel Cloaking BEFORE concluding anything
---

The user watched a ghost test run and reported, verbatim: "the ghosts didn''t have the cloak ability unlocked (just fyi)." This is a direct observation of your fixture and it may be the whole answer, so check it before you build on task 022''s "ability row is inert" result.

The hypothesis it raises: **the ability row read as inert in task 022 because Personnel Cloaking was NOT actually researched in that fixture.** If cloak is not researched, the Cloak button is absent or disabled — and "no key/click emits 0x21" is then a statement about an unresearched ghost, not about the input path or the engine. That would make the earlier "bounded negative" a fixture artefact, exactly the class we keep catching.

What to establish, in order, and it is right in your lane (command-card-from-memory):
1. **Does your fixture actually grant Personnel Cloaking?** Task 022''s `make_test_map.py` fixture was supposed to set it, and 022 claimed the card FINGERPRINT differed with vs without research — but the user is now saying they saw ghosts without it. Reconcile that: read the player''s tech/upgrade state (the researched-abilities bits) out of process memory and confirm cloak is set BEFORE reading the card. If it is not set, your first bug is the fixture, not the card.
2. Once you have a ghost with cloak PROVABLY researched (memory-confirmed, not assumed), read the command-card button array. If the Cloak button now appears and is enabled, the task-022 "inert" reading was the unresearched-fixture artefact and you say so plainly.
3. If cloak is researched AND the button is still absent/disabled/undrivable, THAT is the real finding and it stands.

You are HELD off in-game runs right now (focus-stealing — see my hold message), so do the static half first: find where the player''s researched-abilities live in memory, and how the command card is built from that state. When you need the game to read a live card, you will be released onto task 027''s non-focus-stealing launch — do not launch before then.

This observation is a gift — the user handed you the most likely explanation. Rule it in or out with a memory read rather than assuming either way.
