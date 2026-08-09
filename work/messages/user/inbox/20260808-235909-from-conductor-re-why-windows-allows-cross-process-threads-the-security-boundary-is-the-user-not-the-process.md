---
from: conductor
to: user
sent: 2026-08-08T23:59:09Z
subject: re: why Windows allows cross-process threads - the security boundary is the USER, not the process
---

Because it is a designed capability with a permission model, not an oversight — and the key idea is that **Windows'' security boundary is the user account, not the process.**

**Who legitimately needs this, and would break without it:**

1. **Debuggers.** Setting a breakpoint means writing an `INT 3` byte into another process''s code. Evaluating an expression in the debugger often means running a function in the target. Visual Studio does to your program exactly what we do to StarCraft.
2. **Profilers and crash reporters** — attaching to a running process and instrumenting it.
3. **Overlays.** Steam, Discord, the GPU driver''s framerate counter, OBS game capture — all of them inject a DLL into the game and hook its rendering calls. Structurally identical to what we do.
4. **Accessibility software.** Screen readers and input tools need to reach into other applications.
5. **Anti-virus and EDR** — hooking processes to watch what they do.
6. **Windows itself.** Hot-patching, compatibility shims, and the loader all rely on this machinery.

Removing the capability would mean no debuggers on Windows. It is load-bearing for the whole development ecosystem.

**But it is not unguarded.** To do any of it you must first `OpenProcess` with specific rights — `PROCESS_CREATE_THREAD`, `PROCESS_VM_OPERATION`, `PROCESS_VM_WRITE` — and the kernel checks the target''s security descriptor. In practice:

1. You can do this to **processes running as you**, freely. That is our case: your account launched StarCraft, your account runs scinject.
2. You **cannot** do it to another user''s processes, or to system services, without administrator rights plus `SeDebugPrivilege`.
3. You cannot do it at all to **protected processes** (PPL) — a hardened class used by anti-malware, DRM, and some anti-cheat, where even administrators are refused.

**The philosophical bit, which is the real answer:** process isolation exists to protect users from each other, not to protect you from yourself. Anything running under your account can already read your documents, your browser cookies, your SSH keys. A program that can do all that being able to also poke another of YOUR processes adds no meaningful new power. So the OS grants it and spends its defensive effort on the boundary that matters — between accounts, and between user and kernel.

**Which is exactly why online anti-cheat is a hard problem** and why it looks the way I described earlier: the operating system will not stop injection, because stopping it would break debuggers. So the game has to defend itself, in user space, against an attacker who has the same privileges it does. That is a structurally losing position, and it is why serious anti-cheat has migrated into kernel drivers — moving the fight to a boundary the OS actually enforces.
