# Task 014, round 5: clearing the remaining displacement-0x0B candidates.
#
# label,addrHex
#
# The claim task 014 rests on is "exactly one instruction in this binary reads
# CSprite::selectionIndex, and it is guarded by sprite flag 0x08". FieldSweep at
# displacement 0x0B returns 94 candidate operands (work/scratch/selgfx3/disp0b.tsv);
# most are stack locals or CImage::direction (CImage also has a byte at 0x0B). The
# three below are the ones that could NOT be dismissed by their address range: all
# three sit in the selection module and all three call the selection-graphics
# primitives 0x004E6180 / 0x004E6290 / 0x004975D0, which is exactly the neighbourhood a
# second selectionIndex reader would live in. The last two are the only remaining
# `[reg+0xB]` byte reads outside the image module.
#
# A claim of the form "there is only one" is worth nothing unless the candidates that
# would falsify it were actually looked at. These are those candidates.
selCallerA,0x0049EFA0
selCallerB,0x0049F7A0
selCallerC,0x0049F860
unknownBit0A,0x00458B30
unknownBit0B,0x00472500
