# Task 014, round 7: does unit death bump CUnit+0xA5, and what does it do to the sprite?
#
# label,addrHex
#
# PR #14 review, finding 8: sc_circles' stale-record guards only close the "died while circled"
# window if the engine bumps the uniqueness byte (CUnit+0xA5) when a unit slot is recycled. The
# repo's evidence for 0xA5 covered READ sites only, so that was a model, not a finding.
#
# FieldSweep at displacement 0xA5, write mode, returns exactly ONE instruction in the whole binary
# (work/scratch/selgfx6/dispA5.tsv): 0x004A03FD in the function below. Whatever that function is,
# it is the only thing that can change a unit's uniqueness byte.
unitUniquenessWriter,0x004A0320

# 0x004A0740 is one of the ten callers of 0x004975D0 (remove selection circle) -- a function that
# strips a unit's selection circle is the shape of the death / removal path, which is the other
# half of finding 8.
unitRemovalPath,0x004A0740
