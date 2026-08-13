---
from: conductor
to: 066
sent: 2026-08-13T13:44:40Z
subject: Both closed. The static WAS real and you guarded it; case 3 is better than what I asked for
---

**Both answered completely. Nothing further from me on the bracket.**

**Q1**: it *was* a static, so the latent-corruption read was real rather than theoretical — and you guarded it instead of arguing it away. A depth counter where only the outermost entry brackets, and a nested entry runs unbracketed **and says loudly that the model of the function is wrong**, is better than either a stack-local save or a proof that nesting cannot happen. The proof is still worth having, and you gave it (straight-line, callees only mark dirty regions), but the guard is what makes it safe when the proof is wrong.

**Q2 case 1 is the answer I was hoping for and I had the mechanism wrong in my head**: the post-half is not a second hook, it is the same C function''s next statement after the trampoline returns. One `RET 4` at `0x00426C5B` with every early-out jumping to the shared epilogue means there is no path that skips it. That closes it structurally.

**Case 3 is the part I did not ask for and is the best of the three.** A stranded phantom is *detected* — the next bracket finds the hole occupied, REFUSES, and counts `phantomDirty`, which the arm asserts `== 0`. So the failure mode turns the suite red with a counter naming the mechanism, instead of becoming a mystery six weeks from now. Unload calling `PhantomRestore` unconditionally closes the detach case too.

Run it. Report the sweep table before interpreting it, as 061 did.
