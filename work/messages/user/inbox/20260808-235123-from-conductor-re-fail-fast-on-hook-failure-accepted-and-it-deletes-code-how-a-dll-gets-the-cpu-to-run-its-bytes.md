---
from: conductor
to: user
sent: 2026-08-08T23:51:23Z
subject: re: fail-fast on hook failure (accepted, and it deletes code) + how a DLL gets the CPU to run its bytes
---

**Part 1: your call on hook failure — accepted, and it is better than what we have.**

Agreed, and it has a consequence you may not have intended but which I like: **if we exit on any hook failure, the rollback code becomes unnecessary.** The patched bytes only exist in that process''s memory, so killing the process removes them by definition. Nothing to undo.

So the rule becomes: install six hooks; if fewer than six succeed, log which ones failed and why, tell the user, and terminate. No half-hooked game, no rollback path, less code to be wrong.

One adjustment I would make to the wording: **exit cleanly rather than crash.** A crash gives you a Windows error box and no information; a clean exit lets us write "3 of 6 hooks failed: queueCommand prologue mismatch (expected 55 8B EC..., found ...)" to the log and show it. Same outcome for you, better diagnosis for us — and the deployed launcher already has the message-box path for exactly this. Queued as a small task.

**Part 2: how a DLL gets the process to execute its code. This is the best question you have asked.**

Your model — "the exe runs, and it calls into DLLs" — is how it USUALLY works, but the thing to unlearn is that the CPU cares which file the bytes came from. **It does not.** Once code is mapped into a process, it is just bytes at addresses. Execution goes wherever the instruction pointer goes. "Which module owns this address" is bookkeeping for debuggers and the loader, not a rule the processor enforces.

So there are three separate ways our code ends up running, and they are worth separating:

1. **At load time, by the OS.** The remote thread we created calls `LoadLibraryA`. The Windows loader maps our DLL and, as part of that, calls our `DllMain`. That thread is a thread OF THE GAME PROCESS — we asked for it to be created there. So our first code runs on a thread the game owns, before the game knows anything.

2. **After patching, by the game itself — and this is the important one.** We overwrote the first bytes of `queueCommand` with a jump to our function. Now, when the GAME''s own main thread does what it always does — call `queueCommand` because you right-clicked — it executes that jump and lands in our code. The operating system is not involved. Nobody "asked" for our code to run. The CPU simply followed an instruction, and the instruction happened to point at us.

   That is the whole mechanism. We did not gain the ability to run code; we **redirected code the game was already going to run.**

3. **Threads we start ourselves.** Our observer thread that samples unit state is a normal thread we create — the same as any DLL that spawns a worker.

The mental model that makes this click: a process is an address space with threads wandering through it. A DLL does not "belong" anywhere special in that space, and a thread does not know or care which module it is currently inside. When the game''s thread walks into our function, it is still the game''s thread — same stack, same registers — just executing our instructions for a while, until we hand it back through the trampoline.
