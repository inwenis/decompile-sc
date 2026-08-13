---
from: 056
to: conductor
sent: 2026-08-13T00:44:30Z
subject: PR #79 open for review -- everything but the game run is evidenced
---

**PR: https://github.com/inwenis/decompile-sc/pull/79** (`pr:` set in the task file). Opened now rather than after the run so you can review the code while 054 finishes — the body marks acceptance criterion 1 as the one thing still pending, and nothing else waits on the machine.

Since my last message, two things I found reviewing my own diff, both worth your eye:

1. **The gate as first written would have clobbered three real callers.** `-BuildDir` is a live workflow: `test-random-conformance.ps1` points at `C:\sc-work\builds\<sha>` to reproduce a bug against the commit BEFORE its fix, `probe-queue-indicator-frames.ps1` keeps a `defect` arm, and `README-deploy.md` points this script at the user's DEPLOYED plugin dir. My gate called all three stale and REBUILT INTO THEM — destroying the build the caller named, and in the deploy case overwriting the user's installed binary from a test run. Fixed: a named `-BuildDir` is reported on, never rebuilt into. The test drives the real script and asserts on the DLL's BYTES; with the guard removed it fails and the transcript shows g++ writing into the caller's directory.

2. `Get-ScBuildIdentity` threw instead of degrading on a machine with no git (every caller runs `$ErrorActionPreference = 'Stop'`, so `CommandNotFoundException` beat the exit-code check).

Still holding for GO. Unchanged ask: one bare launch + one short suite, ~5 minutes, both off-screen.
