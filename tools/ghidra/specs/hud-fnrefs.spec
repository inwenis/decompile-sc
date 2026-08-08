# Task 017 round 3: sweep FUNCTION-ENTRY addresses as if they were data, to find the
# instructions that STORE them -- i.e. where the status dialog's controls get their
# interact/update handlers bound after rez\statdata.bin is loaded, and who calls the
# per-frame update pipeline.
#
# Format: label,startHex,byteLength
statusScreenButtonFn,00458220,1
wireframeSelectUpdateFn,00456F50,1
unitStatActSelectionFn,00425960,1
unitStatCondSelectionFn,00424660,1
statDataUpdateFn,00458120,1
statusDialogInitFn,00458570,1
updateSelectedUnitDataFn,004C38B0,1
statDirtyHelper,00458DE0,1
# per-unit-type cond/act table (GPTP stats_display_main.cpp: 3 dwords per unit type,
# 228 types = 2736 bytes)
unitStatFuncTable,005193A0,2736
