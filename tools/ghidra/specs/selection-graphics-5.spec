# Task 014, round 5: clearing the remaining displacement-0x0B candidates.
#
# label,addrHex
#
# The claim task 014 rests on is "every instruction in this binary that reads
# CSprite::selectionIndex is guarded by sprite flag 0x08". FieldSweep at displacement
# 0x0B returns 94 candidate operands (work/scratch/selgfx6/disp0b.tsv); most are stack
# locals or CImage::direction (CImage also has a byte at 0x0B). The three below are the
# ones that could NOT be dismissed by their address range: all three sit in the
# selection module and all three call the selection-graphics primitives
# 0x004E6180 / 0x004E6290 / 0x004975D0, which is exactly the neighbourhood a further
# selectionIndex reader would live in. The last two are byte reads at that displacement
# whose enclosing function was otherwise unclassified.
#
# NOT the last of them: round 6 (selection-graphics-6.spec) covers five more non-stack
# byte reads outside the image module -- 0x00418514, 0x0042E9EC, 0x0042EB97, 0x00435227
# and 0x004723CC -- which an earlier version of this comment wrongly implied did not
# exist. Between rounds 5 and 6 every non-mechanical row of the sweep is read.
#
# A claim of the form "these are all of them" is worth nothing unless the candidates
# that would falsify it were actually looked at. These are those candidates.
selCallerA,0x0049EFA0
selCallerB,0x0049F7A0
selCallerC,0x0049F860
unknownBit0A,0x00458B30
unknownBit0B,0x00472500
