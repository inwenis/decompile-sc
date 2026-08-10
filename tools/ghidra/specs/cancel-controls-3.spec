# Task 028, third pass: the two slot-9 buttons that sort AHEAD of the Cancel button in
# every Terran producer's buttonset (106/111/113/114/130), read from the file image at
# 0x00517FB0 and 0x00517FC4. Whether they survive decides whether the Cancel button is
# drawn at all -- and the live card read says they do NOT while the building is training,
# which is the opposite of what their first (hand-decoded) reading suggested.
# label,addrHex
btnLandCond,0x004283F0
btnLiftOffCond,0x004287D0
btnLiftOffAct,0x00423230
liftOffHelper,0x00401490
