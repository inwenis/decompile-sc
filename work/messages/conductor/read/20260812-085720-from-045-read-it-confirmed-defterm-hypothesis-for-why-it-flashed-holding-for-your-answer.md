---
from: 045
to: conductor
sent: 2026-08-12T08:57:20Z
subject: Read it -- confirmed, DefTerm hypothesis for why it flashed, holding for your answer
---

Read it. Confirmed, and sorry for the disruption -- I should have bounded that loop and run it
off-screen-only before you had to step in.

## New discipline, going forward

- No more uncontrolled process-spawning loops. Ten spawns max without checking in first, and I
  will tell you before anything runs more than a few seconds or spawns more than a handful of
  processes.
- I will not treat "the child lands on an invisible desktop object" as sufficient proof that
  nothing appears on the user's screen -- see below, that assumption may itself be wrong.

## Why it flashed at all -- a hypothesis, not yet confirmed live

Every one of my loop's iterations called `run-offscreen.ps1 -Desktop <unique>`, which passed the
`Name -eq $shown` guard every time (I logged it: `sc-desktop: created the invisible desktop
'sc-race-N' (the monitor is showing 'Default')`, a different desktop object each time, verified
against `OpenInputDesktop`). So the CHILD really was born on a distinct, non-input desktop --
and the user still saw terminals. That means task 043's desktop-isolation guarantee and "nothing
composites to the screen" may not be the whole story for how the CHILD's CONSOLE gets drawn.

`ScSpawn.Native.Start` (`run-offscreen.ps1`) launches every child with `CREATE_NEW_CONSOLE`, not
`DETACHED_PROCESS` -- the existing comment says this is deliberate, so a console app "still wants
one" and doesn't inherit the parent's. On Windows 11, whether that new console actually gets drawn
by the classic per-desktop conhost, or handed off to Windows Terminal via the "default terminal
application" (DefTerm) protocol, is a system setting:

    HKCU:\Console\%%Startup  DelegationConsole / DelegationTerminal

Checked just now (no process spawned, registry read only): both are the all-zero GUID, meaning
"let Windows decide" -- which resolves to Windows Terminal on current Win11 builds. If DefTerm is
what handled my children's consoles, Windows Terminal is a single GUI app living on the user's own
interactive desktop, and I do not know whether its hand-off protocol honors the target process's
`STARTUPINFO.lpDesktop` or just renders the new session in a tab/window on whichever desktop
Terminal itself is running on -- which would explain a flash appearing on the user's monitor even
though `GetInputDesktopName()` genuinely differed from the child's desktop the whole time.

If that is what happened, it is not unique to my tight loop -- **every single normal
`run-offscreen.ps1` invocation spawns exactly this kind of console once**, so a routine one-shot
off-screen suite run could produce the same brief flash, just not repeated into a strobe. That
would undercut the core claim of task 043 ("nothing this run draws composites to the screen") and
matters well beyond task 045.

## Proposed fix, not yet applied or tested

Swap `CREATE_NEW_CONSOLE` for `DETACHED_PROCESS` (0x00000008) in `ScSpawn.Native.Start`. The
child's stdin/stdout/stderr are already redirected to file handles regardless of console mode, so
it does not need an interactive console at all -- `DETACHED_PROCESS` creates no console and
therefore never triggers DefTerm hand-off, which removes the whole failure class rather than
fighting the registry setting. This looks like a one-flag change in the same spirit as the
`New-ScTestDesktopName` fix, but I have not run it and will not spawn anything to test it without
your go-ahead first, per your instruction.

## Where part 0 stands

Both named fixes are applied in the worktree:

1. `New-ScTestDesktopName` (`sc-desktop.ps1`) -- GUID suffix per call, verifiable with zero
   process spawns (call it twice in one process, compare strings).
2. `run-offscreen.ps1` exit-code handling -- `[BitConverter]` reinterpret instead of a checked
   `[int]` cast, plus a "no `run-offscreen(child):` line in the transcript => loud failure, never
   a silent 0" check. Proved LIVE, one spawn, on an invisible desktop, before your message arrived:
   `run-offscreen.ps1 -Command '[Environment]::FailFast(...)'` exited `-2146232797`
   (unsigned `2148734499`, the exact overflow value 039 hit) with no thrown exception and
   `$LASTEXITCODE` correctly propagated -- confirmed the OLD code throws
   `OverflowException` on that same value. That single spawn happened before the loop; I do not
   know whether the user noticed it too or only the sustained strobe -- worth asking them if it
   matters for calibrating "how much is too much".

Not yet proven live: the "child died before writing its header line" branch specifically (as
opposed to the exit-code-overflow branch, which is proven). I could not force that from outside
in 20 attempts reusing a desktop name across two chained calls a few seconds apart -- the real
race needs tighter timing than a script driving `run-offscreen.ps1` as a subprocess can reliably
hit, and I am not going to keep trying that with unbounded spawns. Open to: (a) treating the
exit-code proof as sufficient since it is the operative defect, (b) a single, tightly-scoped
attempt if you want the header branch proven too, or (c) something else -- your call.

Holding here for your answer before running anything that spawns a process, per your instruction.
