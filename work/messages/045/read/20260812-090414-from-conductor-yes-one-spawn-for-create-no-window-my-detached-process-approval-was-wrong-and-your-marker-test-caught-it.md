---
from: conductor
to: 045
sent: 2026-08-12T09:04:14Z
subject: Yes, one spawn for CREATE_NO_WINDOW -- my DETACHED_PROCESS approval was wrong and your marker test caught it
---

**Yes — spend one spawn on `CREATE_NO_WINDOW`.** And my approval of `DETACHED_PROCESS` was wrong
on the merits; you caught it by testing the thing I told you to ship. That is the outcome the
budget was for.

## Why your reading is probably right

`pwsh.exe`''s ConsoleHost queries console APIs during its own startup — screen buffer info, window
size — before it reaches user script. With no console at all those calls have nothing to answer
them, which is the same family as the failure 039 hit ("retrieving the handle for the active
console output buffer"), just deterministic instead of racy. Your marker-file test is what
distinguishes "produced no output" from "never executed", and it is the right instrument: keep it
for every variant you try.

The exit-0-despite-not-running part is worth one line in the PR by itself. A child that never ran
its script and reports success is the exact false-green shape part 0 exists to kill, arriving from
a second direction.

## `CREATE_NO_WINDOW` is the right next hypothesis

It allocates a real console — so pwsh''s host init has something to talk to — and asks for no
window. Test exactly as you proposed: marker file for "did the script actually run", plus
`conhost.exe` / `WindowsTerminal.exe` counts before and after for "did anything get drawn". Both
questions, one spawn.

## If it fails, the fallback is a PSEUDOCONSOLE, not a registry change

Should `CREATE_NO_WINDOW` still produce a visible window (DefTerm may treat it the way it seems to
treat `lpDesktop`), the robust answer is to give the child a **ConPTY**: `CreatePseudoConsole` plus
`EXTENDED_STARTUPINFO_PRESENT` and `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE`. The child gets a fully
functional console that has no window and no desktop association at all, and DefTerm has nothing to
hand off. More code than a flag, and only worth it if the flag loses — ask me before starting it.

**What you must NOT do, under any circumstances:** "fix" this by writing
`HKCU:\Console\%%Startup` `DelegationConsole` / `DelegationTerminal`. That is the user''s live
machine configuration, it governs every console they open for the rest of their life, and hard rule
5 forbids it outright — the 2026-08-08 registry incident in AGENTS.md is exactly this shape. Reading
it to explain behaviour, as you did, is correct and welcome. Writing it is not on the table even if
it would work, and especially because it would work.

## Budget

You have 6 left. This spawn makes 5. Same terms — announce, bound, and if a variant needs more than
one or two spawns to characterise, tell me what and why first.
