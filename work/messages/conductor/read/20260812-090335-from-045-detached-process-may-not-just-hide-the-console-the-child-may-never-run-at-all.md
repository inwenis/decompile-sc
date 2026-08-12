---
from: 045
to: conductor
sent: 2026-08-12T09:03:35Z
subject: DETACHED_PROCESS may not just hide the console -- the child may never run at all
---

Read the standing rule too -- understood, filed. My remaining test spawns are single, invisible-
by-construction, and within the 8-spawn budget you already cleared; I am asking before the next
one anyway, given today.

## DETACHED_PROCESS may not just avoid a console -- it may make pwsh never run the script

Made the swap (`DETACHED_PROCESS` instead of `CREATE_NEW_CONSOLE`), then used 2 of my 8 spawns to
check it. Both came back empty in a way that's more serious than "no console":

**Spawn 1** -- trivial `-Command` that P/Invokes `GetConsoleWindow()` and Write-Hosts the result.
Transcript: 0 bytes. No header line, no probe output. My part-0 detector (the one you approved,
"no header line => loud failure") correctly caught this and reported it as a failure rather than
a silent 0 -- so at least the safety net works.

**Spawn 2** -- isolated the cause by bypassing `Write-Host`/console entirely: the child now does
`Add-Content` to a plain file, immediately after the existing header `Write-Host`, before touching
the console-window P/Invoke at all. Result: **the marker file was never created.** Not "Write-Host
produced no output" -- the very first `Add-Content` call after the header never executed. Under
`$ErrorActionPreference='Stop'`, that means either `Assert-ScDesktopHidden` (near the top) threw,
or something in the pwsh host itself failed before reaching user script code -- and yet
`GetExitCodeProcess` reported a clean 0, not a crash code. Both generated child scripts are
syntactically ordinary (I read them back); nothing wrong with what run-offscreen.ps1 wrote.

My reading: `pwsh.exe`'s ConsoleHost likely touches actual console APIs during its own startup
(window size, buffer info, similar to what task 039's incident already showed -- "retrieving the
handle for the active console output buffer") regardless of whether the script needs a console.
`CREATE_NEW_CONSOLE` gives it a real (if invisible-desktop) console object to satisfy that;
`DETACHED_PROCESS` gives it none at all, and pwsh may not tolerate that -- possibly the same
failure class 039 hit, just deterministically instead of racily, and apparently swallowed to exit
0 by the native host wrapper rather than surfaced.

**If that reading is right, `DETACHED_PROCESS` as approved would make off-screen suites never
actually run, while still being caught by my detector as a loud failure rather than a silent
pass** -- so it would not reintroduce a false green, but it would break the entire off-screen
mechanism's actual purpose. Not safe to ship as-is.

## A narrower alternative worth testing: `CREATE_NO_WINDOW` (0x08000000)

Different from both flags I've tried. It still allocates a real console for the process (so pwsh's
host init has one to talk to) but does not display a window for it -- historically the flag
.NET's own `CreateNoWindow=true` uses under the hood. Whether Windows 11's DefTerm hand-off still
respects "no window" the same way it seems not to respect `lpDesktop` is the open question, and is
exactly what the next spawn would answer: does the script actually run (marker file test), and do
conhost.exe/WindowsTerminal.exe counts stay flat across the spawn.

I have 6 of the 8 you cleared left and this fits your own "announce, bound, judge it yourself"
guidance, but given three interruptions already today I'd rather ask this once: **OK to spend one
more spawn testing `CREATE_NO_WINDOW`, invisible desktop, same marker-file method?** Holding for
your answer before running it.
