# The two controls that can cancel a queued unit, task 028.
#
# label,addrHex
#
# Provenance of every address below -- all read out of THIS binary, none inherited:
#   statusCtrlInteract   0x00457F30 -- the interact bound to status-area control ids 2..6
#                        (and 9..12, 15, 17) by the CREATE-time binder: it is entries
#                        [1..5] of the 44-entry per-index interact table at 0x00504AF0,
#                        which hud-selection-row.md 2 already evidences and which
#                        work/scratch/028/peek.py dumps straight out of .rdata.
#   statusCtrlActivate   0x004573A0 -- the only caller of the 0x20 (Cancel Train) emitter
#                        inside the status module; found by scanning .text for E8 rel32
#                        calls into queueCommand 0x00485BD0 and decoding the command-id
#                        byte each site stores (work/scratch/028/cmdsites.py). Called from
#                        0x00457F75, i.e. from statusCtrlInteract's USER case.
#   statusCtrlCreate     0x00457CA0 -- statusCtrlInteract's CREATE case; binds each
#                        control's fxnUpdate and allocates its statUser record.
#   queueIconUpdate      0x00457480 -- the fxnUpdate statusCtrlCreate binds for control
#                        ids outside 9..12, i.e. for the five queue icons.
#   statusCondBuilding   0x00425180 -- the per-unit-type status cond for a production
#                        building, from the table at 0x005193A0 (hud-selection-row.md 4.2),
#                        row unitId*0xC: identical for 106/111/154/160.
#   statusActBuilding    0x00427890 -- the act from the same rows; the function that
#                        decides which of the status pane's controls are shown.
#   cancelBuildQueueSlot 0x00466A70 -- research/production-queue.md 4.4: the branch
#                        cmdrecvCancelTrain takes for a payload that is not 0xFE/0xFF.
#   cancelLastQueued     0x00466E40 -- the 0xFE branch of the same handler.
#   btnCancelTrainCond   0x00428530 -- the card Cancel button's condition (production-queue.md 3).
#   cardCancelAction     0x00423490 -- that button's action, the other 0x20 emitter.

statusCtrlInteract,0x00457F30
statusCtrlActivate,0x004573A0
statusCtrlCreate,0x00457CA0
queueIconUpdate,0x00457480
statusCondBuilding,0x00425180
statusActBuilding,0x00427890
cancelBuildQueueSlot,0x00466A70
cancelLastQueued,0x00466E40
btnCancelTrainCond,0x00428530
cardCancelAction,0x00423490
