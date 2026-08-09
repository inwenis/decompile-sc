---
from: conductor
to: user
sent: 2026-08-08T23:32:42Z
subject: the trampoline, concretely - real bytes from our own hook, drawn out
---

Let me do it with the actual bytes from one of our real hooks instead of words.

**The target.** We hook the game''s `queueCommand` function. Its first 9 bytes on disk are, verified against this exact binary before we patch anything:

    55 8B EC 51 A1 A0 4A 65 00
    ^^ ^^^^^ ^^ ^^^^^^^^^^^^^^
    |  |     |  MOV EAX,[0x00654AA0]
    |  |     PUSH ECX
    |  MOV EBP,ESP
    PUSH EBP

Those 9 bytes are four complete instructions. That number 9 is not a guess — it is written down from a disassembly, because cutting a machine instruction in half would corrupt the function.

**Three pieces of memory are involved.** Call the function''s address T.

    BEFORE
    T:      55 8B EC 51 A1 A0 4A 65 00 | ...rest of queueCommand...

    AFTER
    T:      E9 <jump to our code>  90.. | ...rest of queueCommand...   <- 9 bytes replaced
    OURS:   HkQueueCommand(...)  {  ...our logic...  }
    TRAMP:  55 8B EC 51 A1 A0 4A 65 00  E9 <jump to T+9>

Read the third line carefully, because it is the whole trick. The trampoline is a **separate scratch buffer we allocate**, containing:

1. a faithful copy of the 9 bytes we were about to destroy, followed by
2. a jump back into the original function at T+9 — i.e. at the exact instruction that came after them.

**So what does "calling the original" do?**

    ((ScQueueFn)g_hkQueue.trampoline)(buf, len);

Execution enters our scratch buffer, runs `PUSH EBP; MOV EBP,ESP; PUSH ECX; MOV EAX,[...]` — the real first four instructions of `queueCommand`, doing exactly what they always did — then hits our jump and lands in the middle of the real, untouched `queueCommand`, which carries on with no idea anything happened. Same stack, same registers, same arguments.

**Why we cannot just "call T" instead:** T now starts with a jump to us. Calling it would bounce straight back into our own code, forever. The trampoline exists precisely to give us a doorway into the original function that does not pass through the patched bytes.

**What the game sees:** the function it calls is still at T, still called the same way. It jumps to us first, we decide what to do, and we can run the original zero, one, or several times through that scratch buffer. That is how one right-click from you becomes several Select+order pairs — we call the original repeatedly.

**Three practical details:**

1. We refuse to install if the 9 bytes at T are not exactly what we expect. If a different game version had a different prologue, we abort rather than corrupt it — that is the `kPrologueQueue` constant in the code.
2. The overwrite happens with the game''s threads suspended, so nobody is executing those 9 bytes mid-swap.
3. On uninstall we write the original 9 bytes back, but we deliberately never free the trampoline — another thread might be inside it at that instant, and freeing memory somebody is executing is a guaranteed crash.

If a piece of this is still murky, tell me which line above stops making sense and I will attack that specific one — this is worth you actually having, since it is the mechanism the entire mod rests on.
