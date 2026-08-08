# Task 017: status-screen / wireframe-row functions to decompile.
#
# Addresses inherited from GPTP hooks/interface/status_display/* and teippi
# offsets_hooks.h; each is verified against this binary by DecompileMany resolving it
# to an exact function entry (resolvedVia=exact-entry) and by reading the output.
#
# label,addrHex
#
# --- the wireframe row's own pipeline ---------------------------------------------------------
# decides whether the multi-unit status display needs a refresh: compares each
# clientSelectionGroup slot's HP/id against the two caches (GPTP UnitStatCond_Selection)
unitStatCondSelection,0x00424660
# refreshes those caches from clientSelectionGroup (GPTP sub_424540)
selCacheRefresh,0x00424540
# THE layout function: walks the status dialog's children to control index 0x21, assigns one
# clientSelectionGroup unit per button, shows/hides the rest (GPTP UnitStatAct_Selection)
unitStatActSelection,0x00425960
# per-button update fn: draws one wireframe from statUser->unkUser_00 (GPTP
# statdata_UnitWireframeSelectUpdate; fragment hook at 0x00456911)
wireframeSelectUpdate,0x00456F50
# border/graphic renderer the above calls with EDI = control (GPTP sub_56D30)
wireframeBorders,0x00456D30
# the CLICK handler for a wireframe button (teippi offsets_hooks.h StatusScreenButton,
# Stdcall<void(Edx<Control*>)>)
statusScreenButton,0x00458220
# --- generic dialog primitives (GPTP unit_stat_selection.cpp helpers) -------------------------
showControl,0x004186A0
hideControl,0x00418700
updateControl,0x0041C400
# --- the selection->HUD copy and console-module neighbours (binary-selection-map.md 3.1, 6.2) -
updateSelectedUnitData,0x004C38B0
hudConsoleReader,0x004C3880
hudTeardown,0x004C3780
# --- teippi's other status-screen hooks, for the dialog's shape -------------------------------
drawStatusLoadedUnits,0x00424BA0
statusScreenDrawKills,0x00425DD0
