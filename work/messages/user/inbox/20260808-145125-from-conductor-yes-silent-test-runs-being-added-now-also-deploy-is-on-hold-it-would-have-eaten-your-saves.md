---
from: conductor
to: user
sent: 2026-08-08T14:51:25Z
subject: yes - silent test runs being added now; also: deploy is on hold, it would have eaten your saves
---

**Sound: yes, being fixed now.** Assigned to the worker that owns the launcher every test suite goes through, so all four suites go quiet at once. Rules I set for it: your DEPLOYED game keeps sound (that is the one you play), any global setting it touches gets restored afterwards even if a run crashes, and there is an escape hatch to run a test with audio when debugging.

**Related, and worth knowing: the deploy pipeline is on hold, twice over.** Review caught that it would have wiped your data on every deploy:

1. First pass: it mirrored the game folder, deleting anything not in the source — your profile and replays included (you already have both sitting there).
2. Worker fixed profiles + replays. Second review pass caught that SAVED GAMES live in a third folder it still missed — found by reading the game binary''s own strings. The fix "passed" its test because the test used a profile as a stand-in for a save, so the one folder that mattered was never exercised.

Now fixing, with a real acceptance bar: save an actual single-player game, deploy twice, prove the save survives and still loads. Nothing gets deployed to your desktop until that passes — a deploy that eats saves is worse than no deploy.

Combat-test-fixture task is running in parallel, unaffected.
