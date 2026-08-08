# Task 017 round 6: the handler-binding walker and the frame drivers around it.
#
# label,addrHex
#
# reads the 0x00504AF0 table; sits right after the wireframe interact fn's jump table
handlerBinder,0x004584C0
# per-frame HUD driver: calls updateSelectedUnitData then statDataUpdate
hudFrameDriver,0x004D93F0
# its two callers
hudFrameCaller1,0x004D9530
hudFrameCaller2,0x004D9840
# console init that calls statusDialogInit 0x00458570
consoleInit,0x004C3BB0
# game-start reset that calls consoleInit
gameStartReset,0x004EED10
# helper the click/act path uses to mark things dirty (tail-called from 0x004C38B0)
statDirtyHelper,0x00458DE0
# mouse-over helper the interact fn calls on BW_EVN_MOUSEMOVE
mouseOverHelper,0x00457DE0
