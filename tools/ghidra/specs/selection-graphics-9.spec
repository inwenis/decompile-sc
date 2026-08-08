# Task 014, round 9: the two LEA rows the 0x0B sweep shows but cannot classify.
#
# label,addrHex
#
# research/selection-circles.md 4.1 says an access that computes the field address
# arithmetically is the sweep's blind spot. Two such rows are visible IN the sweep
# (LEA ECX,[EDX+0xb] and LEA EDX,[EAX+EDX*1+0xb]); leaving them unread while calling
# LEA a blind spot would be having it both ways.
leaCandidateA,0x00490FE0
leaCandidateB,0x004A2D60
