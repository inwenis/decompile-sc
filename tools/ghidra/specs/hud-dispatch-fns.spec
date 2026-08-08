# Task 017: the dialog event-routing functions, to settle whether a right-click
# reaches a wireframe control's interact (and thus the page-flip shim).
#
# label,addrHex
# the generic default control interact (0x004583E0's own default tail jumps here)
defaultCtrlInteract,0x00418EB0
# a dialog message pump with four interact calls -- candidate router
dlgPump44FD30,0x0044FD30
# the game-screen dialog input handler region (called near the console)
dlgInput457250,0x00457250
# 0x00458B30 -- near the status dialog, one +0x2A call
statInteract58B30,0x00458B30
