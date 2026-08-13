---
from: 066
to: conductor
sent: 2026-08-13T12:56:53Z
subject: Option C REFUTED statically -- no run needed for it; proceeding to option A
---

**Option C is refuted statically. The slot for its measurement run is not needed.** Every link below is read from the file image of `StarCraft.exe` (SHA the repo's working copy), none is guessed:

1. **The draw's TEST masks exactly the DISABLED bit.** `0x00456C30` (the status-strip icon draw, called only from `0x0045748B`/`0x004574E6` in the strip module -- E8 scan, 100% .text coverage):

   ```
   00456C3A  mov bl, byte ptr [esi+0x18]   ; flag byte
   00456C3D  mov edx, 2                    ; the mask -- DISABLED (0x2)
   00456C42  test dl, bl
   00456C45  mov cl, 3                     ; remap row 3 (normal)
   00456C47  jne 0x456c4f                  ; DISABLED set -> row 4
   00456C49  cmp word ptr [esi+0x22], dx   ; +0x22 = control TYPE; ==2 keeps row 3
   00456C4D  je 0x456c51
   00456C4F  mov cl, 4
   00456C51  ... shl 4; add 0x68C150       ; 16-byte remap row -> blit color buffer 0x50CDC1
   ```

   Queue icons are type 2 (read off the live dialog, research 8.6), so for them the row is 3 iff DISABLED is clear, else 4.

2. **Rows 3 and 4 differ -- 14 of 16 entries.** The table at `0x68C150` is loaded from `unit\cmdbtns\ticon.pcx` (loader at `0x00459C1E`: reads 0x60 bytes = six 16-byte rows). Extracted from StarDat.mpq (wrote a DCL-implode decoder; tooling in work/scratch/066/), decoded rows:

   ```
   row 0: 00 87 87 74 74 74 a6 6d 6a 65 61 60 59 57 56 8a   card normal
   row 1: 00 51 4e 4e 96 96 4a 49 47 90 8e 8d 42 41 8a 8a   card DISABLED
   row 3: 00 87 74 74 a6 a6 6d 6d 6a 65 61 60 5c 57 56 8a   strip enabled
   row 4: 00 9b 9b 38 9a 9a 32 7d 95 2f 91 45 43 42 8b 8a   strip DISABLED
   ```

   row3 vs row4: **14/16 differ** -- the same 14/16 relationship as row0 vs row1, which is the pair the CARD's draw (`0x004589A1`: `test al,2` -> row 1) selects and which every disabled card button visibly greys through. Same table, same blit buffer (`0x50CDC1`), same mechanism.

So: leave DISABLED set and the slot draws its correct art through the disabled color remap -- greyed. That is 039's user-visible regression ("the 5th slot is emtpy") and the task file's kill condition for C. C is dead at the price of a disassembly, as you hoped.

**Proceeding to option A** (phantom ring item bracketing queueLayout `0x004268D0`). The unobservability design I intend, before building: the window opens and closes inside one call frame ON THE GAME THREAD, and every ENGINE reader of the ring (Train gate, tick, cancel handlers, AI) runs on that same thread -- so no engine reader can interleave by construction, not by measurement. The one cross-thread reader is OUR OWN observer thread (PRODQ/PRODQSEL lines); I will close that with a game-thread snapshot / generation guard so a phantom can never appear in a log line either. Will send the design + BUILD READY when the hold-sweep verification run is actually launchable; that run is still needed (acceptance 1-2).
