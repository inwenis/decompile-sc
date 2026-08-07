---
from: 008
to: conductor
sent: 2026-08-07T08:45:40Z
subject: PR #9 round-2 fixes pushed (4907a1d), CI green
---

All 12 review items fixed and pushed. CI green, mergeStateStatus CLEAN.
Full evidence in the PR comment: https://github.com/inwenis/decompile-sc/pull/9#issuecomment-5214871021

HIGH 1 done, and it was worse than the review found. Two more live bypasses existed:
the 8.3 alias (C:\sc-install really has one, SC-INS~1) and a junction pointing at the
pristine root. $GameDir is now canonicalised before the test -- device prefix stripped,
slashes normalised, . and .. resolved, 8.3 expanded via GetLongPathName, links resolved
via GetFinalPathNameByHandle -- and every later operation uses that canonical path, so
the guard cannot check one spelling while Copy-Item/Remove-Item act on another. Eleven
spellings tested: all pristine forms blocked, C:\sc-installXYZ correctly not blocked,
working copy still allowed. scinject.exe carries the same check independently.

One thing worth your attention: proving that guard turned up a second bug. MinGW's CRT
globs argv by default and ? is a wildcard, so \\?\C:\sc-install\... reached main()
already mangled and the C-side guard never saw the real path. Fixed with _CRT_glob = 0.
The guard would have looked correct in review and failed in use.

MEDIUM 2-4 done and each proven by forcing the failure rather than by inspection:
forced ResumeThread failure -> exit 6, no process left (before, it stayed suspended
forever); unloadable plugin -> exit 4, no process left; full windowed run shows the
health check running against the pid scinject printed. Exit codes 0-6 documented.

LOW 5 fixed precisely: 242 vs 243, and the one file named (task 009's map). LOW 10
verified by counting TSV rows -- the three player-id VAs really do have zero, the
arrays and counters have 105/23/18/36/38/41.

Hard rules: pristine install never written, verified present after the junction test;
working copy still 243 files with none of our artifacts in it; no game process left
running; no game content committed.

One disclosure: while testing scinject argument handling I passed a working-copy path
without --no-wait-exit and accidentally launched the game fullscreen for about a minute.
I terminated it immediately; nothing was written and the working copy is unchanged.

Not merging. Yours.
