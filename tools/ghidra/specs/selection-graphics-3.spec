# Task 014, round 3: which of the two overlays IS the selection circle.
#
# label,addrHex
#
# Round 2 decompiled FUN_004E6180 (the "this unit is now selected" primitive) and found it
# creates TWO overlays and records one of them in a sprite flag:
#
#     if ((sprite[0x0E] & 8) == 0) {              // not already selected
#         sprite[0x0B] = slotIndex;               // <- selectionIndex, at 0x0B not 0x03
#         sprite[0x0E] |= 8;                      // <- "selected"
#         FUN_004D6420();                         // overlay A, untracked
#         if ((sprite[0x0E] & 1) == 0)            // overlay B, tracked by bit 0x01
#             if (FUN_004D7070(playerTbl[u->player], 0x231)) sprite[0x0E] |= 1;
#     }
#
# and that for unit types whose units.dat flags carry 0x20000000 (Invincible -- mineral
# fields, geysers) it creates ONLY overlay B. An invincible unit gets a selection circle and
# no health bar, so overlay B should be the CIRCLE and bit 0x01 its "already attached" record
# -- which would confirm the inherited claim in research/selection-cap.md 2.4. That inference
# is what these four functions have to settle from the binary.
selCircleOrBarA,0x004D6420
selCircleOrBarB,0x004D7070
selGfxRemoveNormal,0x00497620
selGfxRemoveInvincible,0x004975D0
selGfxAlliedInner,0x004E65C0
