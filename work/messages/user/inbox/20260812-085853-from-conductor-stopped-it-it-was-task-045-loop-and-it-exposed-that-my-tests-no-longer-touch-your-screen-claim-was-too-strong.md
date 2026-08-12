---
from: conductor
to: user
sent: 2026-08-12T08:58:53Z
subject: Stopped it. It was task 045 loop -- and it exposed that my "tests no longer touch your screen" claim was too strong
---

Stopped. And it was ours — twice over. Here is the whole thing, including the part where I told
you something that was not true.

## 1. What it was

Task 045 was reproducing a race I had asked it to prove. Its repro was a **50-iteration loop, two
process spawns per iteration**, each one creating a console window — that is your strobe. I killed
the loop process and its children at **08:53Z**; 045 has spawned nothing since (measured: zero new
console processes from it in the three minutes after).

**The acceptance criterion that produced that loop is mine.** I wrote "prove it by making a child
die on purpose" and never said "without putting a window on the user''s screen". 045 should have
bounded it; I should have scoped it. Both true, and the first one is the one I control.

## 2. Why it came back at 08:54

Partly the tail of that loop, and partly something worse that 045 found while investigating —
which is the important half of this message.

## 3. I have to correct something I told you at 07:57Z

I said, about task 043: *"tests no longer touch your screen."* **That was too strong, and 045 has
found the mechanism.**

Every off-screen run spawns a helper process with `CREATE_NEW_CONSOLE` — which asks Windows for a
console window. On Windows 11 your `DelegationConsole`/`DelegationTerminal` settings are both the
"let Windows decide" value, which on current builds means the console is handed to **Windows
Terminal** — and Windows Terminal is an ordinary app living on YOUR desktop. The child process
genuinely is on an invisible desktop; the console window drawn on its behalf may not be.

So: an ordinary off-screen run can still flash one terminal at you. 045''s loop turned one flash
into a hundred, which is why you noticed. The game itself does stay off your screen — that part
was measured and holds — but I overstated the claim, and you were the one who found the hole in
it, twice, by being annoyed.

## 4. The fix, approved and being made now

Spawn the helper with **`DETACHED_PROCESS`** instead: the child gets NO console at all, so there is
nothing for Windows Terminal to draw, on any desktop. Its output already goes to files, so it never
needed an interactive console. One flag, and it removes the whole class rather than fighting a
registry setting.

I have also told 045 how to PROVE it rather than assert it: count console/Terminal processes
immediately before and after a spawn, and check the child''s own `GetConsoleWindow()` is null. A
process with no console cannot have one drawn for it. That is a positive check, not "nobody
complained this time".

## 5. What I have put in place so this cannot recur

A standing rule for every worker: **nothing may create a visible console window on your desktop,
and least of all in a loop.** Concretely — loops run windowless or on an invisible desktop; every
loop is bounded; anything spawning more than a handful of processes or running more than a few
seconds must be announced to me BEFORE it starts, so I can tell you rather than have you discover
it. 045 is on an explicit budget of 8 spawns for the rest of its task.

## 6. Your question: yes, report it to the conductor repo

It is a genuine gap in the orchestration system, not a quirk of this repo: **nothing stops a worker
from spawning unbounded visible windows on the operator''s desktop, and the guard hooks that block
destructive commands have no concept of "this will take over the screen".** That is worth a guard.

I cannot open it myself — `C:/git/conductor` is off-limits to everything in this repo by your own
hard rule 6, and I am not going to make an exception for a convenience. Here is the text, ready to
paste:

> **Guard: workers can strobe the operator''s desktop with spawned consoles**
>
> A worker running a process-spawning loop (reproducing a race, stress-testing a launcher) creates
> a console window per spawn. With Win11 DefTerm delegation those consoles are drawn by Windows
> Terminal on the OPERATOR''S interactive desktop even when the child process is on another
> desktop. 50 iterations x 2 spawns made the machine unusable — continuous focus theft, no way to
> type. Observed 2026-08-12 in decompile-sc.
>
> Suggestions: (a) a guard-hook heuristic that refuses shell commands combining a loop construct
> with a process-spawning cmdlet unless an explicit opt-in flag is present; (b) worker settings
> defaulting spawned children to no-window; (c) a documented rule that any loop spawning processes
> must be announced to the conductor first, which is what I have imposed by hand here.

## 7. One thing I cannot fix, and your lever for it

Some flashing is inherent: every agent runs shell commands, and each one briefly creates a console.
Right now that is about **one every thirteen seconds across five agents** — noticeable if you are
looking, nothing like the strobe. The only lever I have is fewer agents at once. Say the word and I
will drop to two; it costs throughput, not correctness.
