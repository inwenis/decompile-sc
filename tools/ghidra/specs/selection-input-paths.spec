# Task 036 -- the three selection INPUT paths the drag box does not cover.
#
# Task 024 relaxed the client gate for the drag box only (clicked == 0). This spec is the
# set of functions that decide what the OTHER input paths select, so each can be read
# rather than inferred from the box's behaviour.
# Format: label,addrHex
#
# the client selection funnel (research/command-path.md 3.1, building-groups.md 2)
SortAllUnits,0046F0F0
dragBoxHandler,0046FA40
clickSelectHandler,0046FB40
combineSelectionsLists,0046F290
resolveClickedUnit,0046F3A0
applyNewSelect,0046FA00
unit_IsStandardAndMovable,0047B770
# control-group recall, client side (research/control-groups.md 4.1)
hotkeyKeyHandler,00496B40
# the window procedure -- where a double click becomes a message the game acts on
# (research/foreground-input.md / AGENTS.md task 027 quote FUN_004d1d70)
windowProc,004D1D70
