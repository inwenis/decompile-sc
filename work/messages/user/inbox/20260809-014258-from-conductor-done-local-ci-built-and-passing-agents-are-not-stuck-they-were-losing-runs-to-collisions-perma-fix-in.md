---
from: conductor
to: user
sent: 2026-08-09T01:42:58Z
subject: done: local CI built and passing; agents are NOT stuck (they were losing runs to collisions - perma fix in)
---

Both of your asks, done.

**1. Local CI — built, committed, passing.** `scripts/run-ci-local.ps1` reproduces the GitHub workflow exactly (it was pure PowerShell and Python, so nothing in it needed GitHub''s machines): parse every script, validate the JSON, run Pester if present, guard against committed game content, byte-compile the Python, lint. It writes a dated receipt per branch so a merge cites something durable instead of my say-so.

Run and passing on both `main` and the control-groups branch. So merges are no longer hostage to billing — though sorting the billing is still worth doing, since the cloud run is the one nobody can fudge.

Worth being precise about what it does NOT do: it does not run the plugin''s offline tests or the five in-game suites. Those need the game and are the workers'' own evidence. The cloud CI never ran them either — it only ever parsed and linted.

**2. Nobody is stuck — but they were bleeding runs, and that is now permanently fixed.**

Both agents are alive and were writing files seconds before I checked. What was actually happening is worse than stuck and looks like nothing from outside: **they kept destroying each other''s test runs.** All the suites generated their maps into one shared folder, and the map browser picks by ROW, not by name — so whoever''s file sorted first got loaded. One agent ran a whole test against the other''s map and reported confident nonsense; another had its map deleted mid-run. Four runs lost between them today.

Two structural fixes are now repo law:

1. **Each task gets its own map folder.** Your agent 022 worked this out — it removes the interference in both directions instead of scheduling around it. Including the subtle part: delete your folder at the end only if it is empty, because an empty folder of yours becomes the first row for everyone else.
2. **Refuse to start, and re-check again immediately before launching**, if a file you did not create is present. Checking once at the start is checking at the wrong time.

Both agents improved my own rules within an hour of my writing them, which is the system working. Neither invented a "probably fine" — every bad run was voided rather than salvaged.

Next: merging the control-groups work now that there is a green local receipt for it.
