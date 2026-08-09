---
from: conductor
to: user
sent: 2026-08-09T20:01:29Z
subject: your cloak clue paid off - confirmed, and it even caught an error in our own earlier work
---

Quick follow-up because your observation cracked it faster than clicking ever would have.

**You were exactly right, and it is stronger than "not unlocked."** We read the command card straight out of the game''s memory instead of looking at the screen. The Cloak button IS there (it''s the 7th slot, and the code behind it is byte-for-byte the cloak command) — but it''s GREYED OUT. And a greyed button is silent to every key and every click by the game''s own design. So the reason our test "couldn''t trigger cloak" was never an input problem — the button was disabled.

**Why disabled: the test''s ghosts genuinely did not have cloak researched** — exactly what you saw. Our map generator set a "cloak is available" flag but not the "cloak is researched" flag the game actually checks, so the button showed up but stayed greyed. That''s a bug in our test setup, now being fixed so a future test ghost really can cloak.

**And your FYI caught a mistake in our OWN earlier work.** A previous task had concluded, from comparing screenshots, that the researched and unresearched ghosts drew different command cards. Reading the actual memory shows they''re identical — both greyed. The screenshot comparison was a false positive. That''s now corrected, and it''s become a standing rule: read what a menu shows from memory, never from a picture of it.

**One honest distinction:** this explains why our TEST couldn''t cloak. It does NOT yet explain your original report — a ghost in your real game that WAS cloaked and stopped attacking. That one still needs the proper test on a genuinely-cloaked ghost, which is queued behind the focus-fix. But the mystery of "why can''t we even drive the button" is fully solved, and you solved it.

Thank you — a one-line FYI saved a worker a lot of guessing and exposed a real error we''d have carried forward.
