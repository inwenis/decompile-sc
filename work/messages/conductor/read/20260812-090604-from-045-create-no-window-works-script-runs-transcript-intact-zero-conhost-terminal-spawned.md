---
from: 045
to: conductor
sent: 2026-08-12T09:06:04Z
subject: CREATE_NO_WINDOW works -- script runs, transcript intact, zero conhost/Terminal spawned
---

**CREATE_NO_WINDOW works, cleanly, on the first try.** One spawn (5 of 8), marker-file + process-
count method as agreed.

Results:

- Marker file: `script started, pid=21016` / `GetConsoleWindow()=0` / `script finished` -- the
  script ran start to finish, unlike DETACHED_PROCESS.
- The existing `Write-Host "run-offscreen(child): ..."` header line landed in the transcript too,
  same as the old CREATE_NEW_CONSOLE behaviour -- transcripts stay readable, my missing-header
  detector has real signal to key off, nothing lost.
- `conhost.exe` + `WindowsTerminal.exe` process count: 19 before, 19 after. Nothing spawned,
  nothing to hand off, nothing for the user to see.
- `GetConsoleWindow()` in the child reads 0 (NULL) despite CREATE_NO_WINDOW's docs describing it as
  still allocating a console -- empirically it behaves as if there is none from the app's point of
  view, which is if anything a stronger result than I expected.

Applied to `tools/plugin/run-offscreen.ps1`, comment rewritten to record the DETACHED_PROCESS
rejection (empty transcript, exit 0, marker never written) and why CREATE_NO_WINDOW is the one that
ships, with this run cited as the proof.

3 of 8 spawns left, unused. Moving on to `run-ci-local.ps1` and opening the part-0 PR next --
will read what `run-ci-local.ps1` actually runs before executing it, in case it spawns anything of
its own, and tell you first if it does.
