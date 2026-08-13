---
from: 066
to: conductor
sent: 2026-08-13T13:44:10Z
subject: ON the machine; both bracket questions answered (reentry guard committed 4b217f6)
---

**ON the machine now** -- launching the hold-sweep run (off-screen, one launch, ~10-15 min expected). Will message OFF.

**Q1 -- per-call or global save?** It was a static (global), and your latent-corruption read was right, so it is now guarded rather than argued away: commit `4b217f6` adds a depth counter to the detour -- only the OUTERMOST entry applies and restores; a nested entry runs the original UNBRACKETED and logs loudly ("this model of the function is wrong; investigate"). For the record, no nesting path is known: queueLayout is straight-line (its callees -- enable/disable/updateControl/sprintf -- mark dirty regions, they never re-dispatch a layout), and the bracket runs on one thread. The guard makes the static safe under that model being wrong, which is the standard you asked for.

**Q2 -- what if the original does not return normally?** Three cases:

1. **Every survivable path RETURNS.** queueLayout has one exit (`RET 4` at `0x00426C5B`); all its early-outs (`0x426918 -> 0x426c56`, the not-our-unit case included) jump to the shared epilogue and return through it -- read off the disassembly, quoted in sc_addresses.h. Our detour regains control after the trampoline call on every one of them, so the restore runs regardless of which internal path was taken. There is no early return that skips the post-half, because the post-half is not a second hook -- it is the same C function's next statement.
2. **A fault inside the call** unwinds past the restore -- and past the game: no engine SEH handler survives a fault in the layout path, so this is a crashed process, not a live game with a stale ring.
3. **And if a phantom ever DID strand** (some path outside this model): it is detected, not silent. The very next bracket finds the slot non-empty where the overflow map expects a hole, REFUSES to write, and counts `phantomDirty` -- which the regression arm asserts `== 0`, so a stranded phantom turns the suite red with the counter naming the mechanism. Unload also calls PhantomRestore unconditionally, so a mid-game detach cannot strand one either.
