# The command card's refusal-code global, task 025 (the 4.1 correction).
#
# label,startHex,byteLength  (XrefSweep takes RANGES; the length is DECIMAL)
#
# 0x0066FF60 is what the requirement gate 0x0046E1C0 writes before each of its `return 0`
# paths (0x10 "id out of range", 1 "not your unit", 2 "no tech", 4 "needs an addon", ...):
# the engine's own "why the command card said no" channel. Every OTHER writer of it is
# another client-side refusal, so this sweep enumerates the candidates for the one that
# greys the Train button out at five queued.
#
# Result: 143 references, 17 writing functions -- the six requirement gates in 0x0046Dxxx
# / 0x0046Exxx, the receive handlers in 0x004C1xxx, and two button conditions. None of the
# seventeen appears in research/data/production-queue-fields.tsv, i.e. none of them reads
# the ring. Negative, like production-clientgate.spec.

requirementError,0x0066FF60,4
