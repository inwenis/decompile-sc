---
from: conductor
to: user
sent: 2026-08-08T23:03:33Z
subject: how the mod actually works: no, we never touch StarCraft.exe - we inject a DLL and redirect functions at runtime
---

Good question, and the answer is the thing I am proudest of in this setup: **we never modify StarCraft.exe. Not once, not ever.** The file on your disk is byte-for-byte the original 1.16.1 executable, and every test we run re-verifies its SHA-256 before and after. No patched binary, no recompiled assembly, no modified game files.

**What actually happens when you double-click the shortcut:**

1. A small launcher starts the real, unmodified StarCraft.exe.
2. A second small program (`scinject.exe`) tells Windows to load OUR library — `scplugin.dll` — into the running game''s memory.
3. Our DLL then does the actual trick: it finds a handful of specific functions inside the game''s code, and **redirects them to us**. In practice that means overwriting the first 5 bytes of a function with a jump to our own code, and keeping the original bytes so we can call the real function afterwards. It is called a detour, or a hook.
4. All of that happens in MEMORY, in the running process. Close the game and every trace is gone.

**So the mod is not a changed game — it is a passenger riding inside the unchanged game.**

We currently hook six places, and each maps to something you can see:

| what we hook | what it gives you |
| --- | --- |
| the "commit this selection" function | we notice you selected 24 units and remember all of them |
| the "queue this command" function | one order becomes several, so all 24 obey |
| the selection-rebuild function | the extra units keep their green circles |
| the HUD status dispatcher | the bottom row pages through more than 12 |

**Why this approach rather than patching the executable:**

1. **Reversible.** Passive mode (`-Mode observe`) installs zero hooks and you get a bit-perfect vanilla game from the same files.
2. **Safe to be wrong.** A bad patch on disk means a broken install and a reinstall. A bad hook means one crashed session.
3. **Verifiable.** "The exe is unchanged" is a claim we can and do test automatically every single run.

**The part that took the real work** is not the hooking — it is knowing WHERE to hook. StarCraft 1.16.1 has no source code available to us, so every address in that table was found by disassembling the binary and proving what each function does: that is what the `research/` folder is, and why I keep insisting every offset carries evidence of how it was found AND how it was verified. When we get that wrong, we get exactly the bugs you have seen me chase today.

Your three new mod ideas are queued — separate message.
