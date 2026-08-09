---
from: conductor
to: user
sent: 2026-08-08T23:43:48Z
subject: re: how we get to run our code at all - and you are right that uninstall is nearly pointless
---

**Part 1: how our code gets to run, and how it is allowed to write at T.**

The step that makes everything else possible is that our DLL ends up INSIDE the game process. Once it is inside, there is no "their memory" and "our memory" — there is one address space, and `0x004C0860` means the same thing to us as it does to the game. Writing to it is then an ordinary memory write.

Getting in is done by `scinject.exe`, and it is a standard Windows sequence:

1. `OpenProcess` — get a handle to the running game.
2. `VirtualAllocEx` — allocate a small buffer INSIDE the game''s memory.
3. `WriteProcessMemory` — write the string `"C:\...\scplugin.dll"` into that buffer.
4. `CreateRemoteThread`, pointed at Windows'' own `LoadLibraryA` function, with our string as its argument.

That last step is the trick: we ask the operating system to start a thread in the game that calls the normal "load a DLL" function. Windows loads our DLL exactly as if the game had asked for it, and calls our `DllMain`. From that moment our code is running in the game, on equal terms with it.

**The one extra permission we need:** code pages are mapped read-and-execute, not writable — the CPU will fault if you write to them. So before patching we call `VirtualProtect` on those few bytes to make them writable, do the write, and put the protection back. That is a normal Windows API any process can call on itself; there is nothing exotic or privileged about it.

So the honest summary: **we are not breaking in. We are asking Windows politely, and Windows says yes, because a process is allowed to modify itself.** That is also exactly why anti-cheat systems exist for online games — the OS will not stop this, so the game has to look for it. Offline, nobody is looking.

**Part 2: you are right about uninstall, and I will not defend it as a feature.**

You are correct that "remove the mod from a running game" is not a thing you will ever want, and we already concluded the same from a different direction: an earlier review found that unloading mid-game was genuinely unsafe, and we documented mid-game unload as UNSUPPORTED rather than fixing it.

The uninstall code earns its place for one unglamorous reason: **rollback on a failed install.** We install six hooks. If the fourth fails — a prologue does not match what we expect, a memory protection call is refused — we must put the first three back and abort cleanly, or you get a half-hooked game where some features are live and others are not. That is a real failure mode and a very confusing one to debug.

It also gets used by the offline test suite, which installs and uninstalls hooks against fake memory hundreds of times per run.

But as a user-facing feature? Agreed — it is not one, and it is not advertised as one. Closing the game is the supported way to remove the mod, and that costs nothing since none of this touches your disk.
