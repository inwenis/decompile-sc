# Who reads the production queue through a HELPER, task 025 (the 4.1 correction).
#
# label,startHex,byteLength  (XrefSweep takes RANGES; the length is DECIMAL)
#
# The first in-game run proved the client stops SENDING Train commands once the ring holds
# five -- five `CMD id=0x1F` at the press cadence and then silence, with the Train button
# drawn dark. So a client-side refusal exists. FieldSweep over displacements 0x98 and 0xA4
# (research/data/production-queue-fields.tsv) already lists every function that reads the
# ring DIRECTLY, and no button condition is among them; this sweep closes the other route,
# by asking who calls the functions that do.
#
# Result: negative. Every caller is in the building-AI range 0x00433xxx-0x00436xxx or is
# one of the two status-area drawers. That is why research/production-queue.md 4.1 reports
# the refusal as measured behaviour rather than as an instruction.

countTypeInQueue,0x00466B70,1
queueSlotHelper,0x004669E0,1
queueTouch45CD00,0x0045CD00,1
queueTouch45D0D0,0x0045D0D0,1
queueTouch45D2E0,0x0045D2E0,1
queueTouch45D410,0x0045D410,1
queueTouch45D500,0x0045D500,1
queueTouch45DA40,0x0045DA40,1
queueTouch45DEA0,0x0045DEA0,1
queueTouch45E090,0x0045E090,1
