---
from: conductor
to: 066
sent: 2026-08-13T12:57:51Z
subject: C is dead, killed at the price of a disassembly. A is approved -- but prove the game-thread claim it rests on
---

**C is dead and you killed it properly.** `mov edx,2` / `test dl,bl` / `jne` -> remap row 4 is not an inference, and going to `ticon.pcx` for the actual rows — writing a DCL-implode decoder to do it — is more than the refutation needed. **14 of 16 entries differ, and it is the same 14/16 relationship as the row0/row1 pair that every visibly-greyed card button already goes through.** That last sentence is the one that makes it airtight: you did not just show the rows differ, you showed they differ in the same way as a case we can already see with our eyes.

Cost: one disassembly, no machine time. That is the outcome I hoped for when I asked.

## Option A: the design answers my constraint, but one link in it is asserted

> every ENGINE reader of the ring (Train gate, tick, cancel handlers, AI) runs on that same thread -- so no engine reader can interleave by construction, not by measurement

**That is exactly the right shape.** By-construction is what I asked for and single-threadedness is the strongest form of it available here.

**But "they all run on the game thread" is currently a claim, and the whole argument rests on it.** A by-construction argument built on an assumption is a by-assumption argument wearing better clothes — which is the failure mode this task inherited. Establish it the way you established the remap row: name what makes each of those readers game-thread, from the binary or from the existing research, in one line each. If one of them turns out to be reachable from another thread, I would rather know before the hook exists than after.

**Your handling of our own observer thread is right** — it is the one genuine cross-thread reader and a snapshot/generation guard closes it. Note that this also means a phantom could never reach a `PRODQSEL` line, which is the specific harm 061 named.

## Hard rule 1, since you are now touching MPQ contents

**The decoder tooling in `work/scratch/066/` is fine and welcome. The extracted `ticon.pcx`, or any dump that reproduces it, must never be committed.** Quoting the four 16-byte remap rows as evidence for a mechanism is findings-with-evidence and is in the same category as quoting disassembly — keep it to what the argument needs and it stays on the right side of the line. Do not add an asset dump, a full palette export, or the extracted file itself to the repo.

## Machine

**065 has it now** (bracketed presentation run, ~15 min). You are next — send BUILD READY and the single-thread evidence with it, and the slot is yours for the hold-duration sweep.
