---
from: conductor
to: user
sent: 2026-08-08T23:21:55Z
subject: re: do we really keep the originals? yes - here is the exact mechanism, from our own code
---

You are right to push on that, and the answer is: **both things are true at once**, which is the whole trick. It is called a trampoline. I checked our actual code rather than answering from memory.

**What happens when we install a hook** (`tools/plugin/src/sc_hook.cpp`):

1. We pick a target function, say the game''s "commit this selection" at `0x004C0860`.
2. Before touching anything, we **copy the first N bytes of that function into a separate piece of memory we allocate** — that copy is the trampoline (`memcpy(tramp, target, patchLen)`, line 108).
3. Immediately after the copied bytes we write `0xE9`, a jump instruction, pointing back into the original function just past the bytes we are about to overwrite (line 109).
4. Only THEN do we overwrite the start of the real function with our own `0xE9` jump to our code (lines 124-128).

So the original function''s body is untouched — we only clobbered its first few bytes, and we kept a faithful copy of exactly those bytes, followed by a jump back to where they left off.

**Calling "the original" then means calling the trampoline**: it runs the real first instructions, then jumps into the rest of the real function. In our code that is literally:

    ((CmdactSelectFn)g_hkSelect.trampoline)(count, units);   // sc_fanout.cpp:903
    ((ScQueueFn)g_hkQueue.trampoline)(buf, len);             // sc_fanout.cpp:796

**Why "replace" is the wrong word:** a replacement would mean the original behaviour is gone. What we actually have is an interception, and we choose per call what to do:

1. **Call it after us** — we look at the selection, remember all 24 units, then let the game commit its 12 as normal.
2. **Call it several times** — the fan-out: one order from you becomes several Select+order pairs, each going through the trampoline.
3. **Not call it at all** — we suppress the original command when we have already replayed it ourselves; that is exactly how "one order reaches 24 units" avoids also sending your original order twice.

**Two details from our implementation worth knowing**, because both are places this technique bites:

1. We never guess how many bytes to copy. Chopping an instruction in half would corrupt the function. The byte count for each hook is taken from a disassembly and written down as a constant (`sc_hook.h` says exactly this).
2. When we uninstall, we put the saved bytes back — but we **deliberately leak the trampoline** rather than freeing it, because another thread could still be executing inside it at that moment. Freeing it would be the classic crash.
