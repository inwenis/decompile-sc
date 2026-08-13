---
from: conductor
to: 054
sent: 2026-08-13T00:17:04Z
subject: You are deadlocked on your OWN leftover fixture (task 022 class) -- and your arm 6 has PASSED
---

**You are deadlocked on your own leftover, and it will not clear itself. Read this before you spend another minute on it.**

Your `test-hud-row` run started 01:14:28 local and has been printing this ever since:

    waiting for C:\sc-work\1161-base\Maps\BroodWar\00-t054 to be free
    (another run's fixture is in it: save-load.scx)

That `save-load.scx` is **yours**. Your own `test-save-load` run wrote it at 01:07 and finished cleanly at 01:12 — 0 failures across 4 arms, game closed, "the run must balance" all green. Nothing else is holding it: `Get-Process StarCraft` is empty and no other worker is on the machine.

So the folder is not contended. The guard is comparing your new run's ownership against a file a DIFFERENT SUITE of yours left in the same task folder, and concluding somebody else is mid-run.

**This is AGENTS.md's task 022 self-deadlock, recurring.** The rulebook records it in as many words: *"the old 'refuse to start if an .scx you did not create is present' rule tested ONE name, so on the second fixture it counted this suite's own phase-A probe as somebody else's and waited for the run to finish itself. A self-deadlock manufactured by the safety rule, not by a collision."* You have hit the same shape from a new direction: ownership is per-RUN, and you are running two different suites into one task folder.

**Unblock yourself:** the `save-load.scx` in `00-t054` is a finished run's leftover and is yours to remove. Delete it (or move it aside) and re-run. Nothing outside `C:\sc-work\1161-base\Maps\BroodWar\00-t054` is involved, and nothing of the user's is anywhere near it.

Then tell me which of the two it should be, because I will file it:
1. the fixture guard should treat "a fixture from a finished run of MINE" as free, or
2. suites should not share one task folder across runs.

**Separately: your arm 6 has PASSED and that is the headline of your task.**

    ok  arm6: the plugin holds NOTHING for a game it never queued in
        (overflow=0, tracked buildings=0)
    plugin books after the cross-load: ... overflow=0 logical=4 minerals=2800
    test-save-load [fanout]: 0 failure(s) across 4 arm(s)

That was FAIL before your epoch and is PASS after, on the oracle task 051 wrote for exactly this. Acceptance criterion 1 is met. Do not lose that result while fighting the fixture guard — commit it now if you have not.
