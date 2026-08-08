# Task 017 round 7: the generic bind-interact-handlers-by-index utility and friends.
#
# label,addrHex
# EDI = 44-entry fn-pointer table 0x00504AF0; generic dialog utility
bindInteractByIndex,0x00418100
# called by handlerBinder 0x004584C0 after the bind
statButtonsInit,0x004C35F0
# per-control-type default interact table users; the dialog-load fixup callback
dialogLoadFixup,0x004D27A0
# dialog-create-from-template (called with the fixup in statusDialogInit)
dialogRunModal,0x004194E0
