# Task 014, round 4: who READS CSprite::selectionIndex, and the two image-init helpers.
#
# label,addrHex
#
# Round 3 settled which overlay is the circle. FUN_00497620 (the deselect primitive) removes
# TWO images and clears TWO flag bits:
#
#     if (!(sprite[0x0E] & 8)) return;                 // not selected -> nothing to undo
#     sprite[0x0E] &= ~8;
#     walk sprite[0x1C] (first_overlay) for image drawfunc == 0x0B  -> free it
#     if (sprite[0x0E] & 1) {
#         sprite[0x0E] &= ~1;
#         walk sprite[0x20] (last_overlay) for imageId in 0x231..0x23A -> free it
#     }
#
# The 0x231..0x23A range is ten consecutive image ids -- the ten selection-circle sizes -- and
# it is the image FUN_004E6180 creates with FUN_004D7070(playerTbl[player], 0x231) under the
# 0x01 bit. So bit 0x01 IS "selection circle attached", exactly as research/selection-cap.md
# 2.4 inherited from BWAPI/GPTP, now confirmed against this binary.
#
# What is still open is the HAZARD: which instructions READ sprite[0x0B]. FieldSweep over
# displacement 0x0B (work/scratch/selgfx3/disp0b.tsv, 94 candidate operands) leaves these as the
# only readers outside the image module -- and FUN_004E6140 sits immediately in front of
# FUN_004E6180, which is where a selectionIndex consumer would live.
selIndexReaderA,0x004E6140
selIndexReaderB,0x0046FB40
selIndexReaderC,0x00499210
selIndexWriterD,0x004997A0

# --- the two image-init helpers, to name the overlays for the record -------------------------
imageInitCircle,0x004D6810
imageInitHpBar,0x004D6010
