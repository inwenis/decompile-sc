# Task 014, round 8: the two functions research 4.5 annotated without an artifact.
#
# label,addrHex
#
# PR #14 round-2 review, finding 5. Section 4.5 quoted the tail of the unit-removal path
# (0x004A0740) as if it ran unconditionally, and labelled 0x0049A7F0 "drop the unit from every
# player's selection" with nothing behind the label. Both are load-bearing: 4.5 is the reason the
# died-while-circled window is closed, so the exact condition under which the engine takes our
# circle off has to be read, not paraphrased.

# The guard on the whole removal tail: `iVar1 = FUN_004a0080(); if (iVar1 == 0) { ... }`
removalTailGate,0x004A0080

# Called first in that tail, immediately before 0x0049F7A0 and 0x004975D0.
dropFromSelections,0x0049A7F0
