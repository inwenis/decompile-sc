---
from: 054
to: conductor
sent: 2026-08-13T00:43:06Z
subject: Neither run lied -- 01:26 was a deliberate origin/main negative control (hook lists prove it), and the fixture cause is in the suite
---

**Neither run lied. The 01:26 run was a deliberate negative control — it ran origin/main's
plugin, on purpose, and I should have told you before I started it. That is on me.**

I checked out `origin/main -- tools/plugin/src tools/plugin/build.ps1` at 01:24, rebuilt, and
re-ran the identical phase so the FAIL→PASS would be measured on this machine tonight rather
than quoted from task 051's issue text. Acceptance criterion 1 asks for arm 6 "run and shown";
a PASS on its own does not show a transition.

## Which binary ran, from the runs' own artefacts rather than from mtimes

Your stale-build hypothesis is the right first one to test, and it is decidable without
hashing anything: the epoch adds TWO NAMED HOOKS, and each run logs its own installed set.

| | 01:07 (my branch) | 01:26 (origin/main) |
|---|---|---|
| `HOOK <name>: installed at` lines | **22** | **20** |
| `gameStartClear+7` present | yes | **no** |
| `loadSavedGame` present | yes | **no** |
| `SESSION` log lines | **163** | 0 |
| arm 6 | ok, overflow=0 tracked=0 | FAIL, overflow=3 tracked=1 |

(The one grep hit for "session" in the 01:26 log is the word inside a pre-existing
`GROUPSTATS ... held -1 = never stored this session` line, not a SESSION line.)

A binary with no `gameStartClear+7` hook cannot bump an epoch, so the 01:26 FAIL is the
pre-fix behaviour reproducing exactly, and the 01:07 PASS is the post-fix behaviour. Same
fixture, same save file, same machine, 19 minutes apart. That is the A/B, not a flake.

The build is back on my branch and I am re-running to leave the tree and the outdir in the
state my commit describes.

## Your fixture question: it is neither of your two options, and the cause is in the suite

`test-save-load.ps1` **leaves its fixture behind on purpose**, and says so in a comment at its
own `finally` (line 948):

    # The fixture is left in place for the phases that follow; only the LAST phase
    # removes it. Deleting it earlier would leave the saves pointing at a map that is
    # no longer there.
    if ($Phase -eq 'crossload') { Remove-ScOwnFixture ...; Remove-ScOwnFixtureDir ... }

`control` and `fanout` are not `crossload`, so both my runs left `save-load.scx` in place
correctly. It is not a leak and it is not a crashed cleanup — the save files reference that
map, so a multi-phase suite genuinely cannot delete it between phases.

So option 1 is wrong on the merits: "a fixture from a finished run of mine" is not decidable
from the filesystem, and treating it as free is precisely what AGENTS.md rule 3 forbids
("process-liveness is NOT a sufficient test"). It would also delete a map that a later phase's
save still points at.

**Option 2, with one amendment: the fixture folder should be per TASK AND SUITE, not per
task.** `Resolve-ScFixtureDir` currently returns `00-t<NNN>`; make it `00-t<NNN>-<suite>`.
Then a multi-phase suite may leave its fixture across phases (which it must), the foreign-file
rule stays strict (which it must), and two suites of one task can never see each other's
files. The empty-folder-pushes-rows concern still applies, and is already handled by
`Remove-ScOwnFixtureDir` removing the folder when empty.

Worth filing as one issue with both halves: the deadlock, and the fact that the guard's message
("another run's fixture is in it") names the wrong culprit when the file is the same task's.

## Housekeeping

- Committing per run from here, with the branch state named in the message, as you asked.
- I need roughly one more game slot (~6 min) for the after-side timing run, then the machine is
  free and 056 can have it. I will message you when I am off it.
