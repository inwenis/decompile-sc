---
from: conductor
to: user
sent: 2026-08-08T23:56:39Z
subject: re: remote threads - and the key correction: loading a DLL DOES run its code
---

Three things to untangle, and one of them is a genuine correction to your model.

**1. "sc.exe asks to load our dll" — it never does. WE ask, from outside.**

A **remote thread** means: a thread created in ANOTHER process. `CreateRemoteThread` is a Windows API where you hand it (a) a handle to some other process, and (b) an address of a function to run, and Windows creates a thread inside THAT process which starts executing at that address. It is the game''s thread, in the game''s address space, but the game never requested it — `scinject.exe` did, from the outside.

The function we point it at is `LoadLibraryA`, which is already sitting in the game''s memory (every Windows process has kernel32 loaded, at the same address, so we know where it is). Its argument is a string — the path to our DLL — which we wrote into the game''s memory beforehand.

So the sequence is: **an outside program forces the game to call LoadLibrary on our DLL.** The game''s own code plays no part and never consented.

**2. The correction: loading a DLL DOES run its code. Automatically.**

This is the piece your model is missing, and it is not exotic — it is the normal DLL contract. Every DLL may export a function called `DllMain`, and the Windows loader **calls it as part of loading**, before `LoadLibrary` even returns. It is called with a reason code: `DLL_PROCESS_ATTACH` when the DLL is loaded, `DLL_PROCESS_DETACH` when it is unloaded.

So "map it into memory" and "run some of its code" are not two separate steps you can have one without the other. Loading is what triggers our `DllMain`, and inside that function we do our work: verify the prologues, patch the six hooks, start our observer thread.

This is ordinary DLL behaviour that every DLL on your machine participates in — we are not abusing anything. The unusual part is only WHO asked for the load.

**3. "Do we have a wrapper that runs before any sc.exe code?" — No, and we do not need one.**

We are not first, and we do not try to be. The real order is:

1. `run-with-plugin.ps1` starts StarCraft.exe normally. The game boots, runs its own startup code, gets to the main menu.
2. A few seconds later (`scinject --wait-ms 4000`), `scinject.exe` injects our DLL into the already-running game.
3. Our `DllMain` patches the six functions.
4. From then on, whenever the game calls one of those six, it arrives in our code.

So the game has already executed a great deal of its own code before we exist. That is fine, because we do not need to precede it — we need to be present at the moment it calls one of the six functions we care about, and those get called constantly during play, long after startup.

There IS a technique for being first (start the process suspended, inject, then resume), and it matters when you must hook something that happens during startup. We do not, so we use the simpler approach.
