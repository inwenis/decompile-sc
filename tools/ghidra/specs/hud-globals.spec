# Task 017: HUD/status-screen globals named by GPTP + BWAPI, swept to find the
# status-screen dialog code in this binary (creation, per-frame update, click dispatch).
#
# Format: label,startHex,byteLength
#
# hudStatState covers the cluster of small globals GPTP's status_display hooks name:
#   0x0068C1E5 "everything hidden" state byte (unit_stat_selection.cpp UnitStatAct_Selection)
#   0x0068C1F8 bCanUpdateStatDataDialog -- the status dialog dirty flag (stats_display_main.cpp)
#   0x0068C1FC wireframe grp/data structure pointer (unit_stat_selection.cpp Part1)
#   0x0068C208/0x0068C20A palette remap bytes used by the wireframe colour writers
# Swept as one range because they sit within 0x50 bytes of each other and any function
# touching one is status-screen code.
hudStatState,0068C1E0,80
# u32[12] -- per-slot HP cache the refresh condition compares against
# (GPTP unit_stat_selection.cpp selectionHPvalues)
selectionHPCache,006CA94C,48
# u16[12] -- per-slot unit-id cache, same role (selectionIDvalues)
selectionIDCache,006CAD7C,24
# dialog* -- head of the game's global dialog list (BWAPI Offsets.h:95 DialogList)
dialogList,006D5E34,4
# dialog*[19] -- per-event-type target dialogs (BWAPI Offsets.h:150 EventDialogs, BW_EVN_MAX=19)
eventDialogs,006D5E40,76
# Control* -- popup dialog (teippi offsets.h:526)
popupDialog,006D5BF4,4
