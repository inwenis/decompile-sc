# Task 026, round 3: the CONDITION and ACTION functions the Ghost's own buttonset points
# at, read out of the buttonset table at 0x005187E8 by work/scratch/card/dump-buttonsets.ps1
# (which reads the file image directly). The layout function 0x004591D0 calls the condition
# with the portrait unit and uses its sign: 0 = button not shown, >0 = shown ENABLED,
# <0 = shown GREYED. So these are the functions that decide whether Cloak is clickable.
#
# label,addrHex
#
# --- conditions -------------------------------------------------------------------------
# the basic-card condition, shared by Move/Stop/Patrol/Hold on every unit
condBasic,0x004282D0
# Attack's condition
condAttack,0x00428F30
# Ghost Cloak's condition (button slot 7, conditionParam 0x0A = Personnel Cloaking)
condCloak,0x004293E0
# Ghost Decloak's condition (same slot 7, conditionParam 0x0A)
condDecloak,0x00429370
# the condition Stim (Marine) and Lockdown (Ghost) share -- a researched-tech ability
condTechAbility,0x004294E0
# Nuclear Strike's condition
condNuke,0x00428810
# --- actions ----------------------------------------------------------------------------
# Ghost Cloak's action -- expected to put command 0x21 on the wire
actCloak,0x00423730
# Ghost Decloak's action
actDecloak,0x00423270
# Stim's action, the one already proven live to emit 0x36 (ability-semantics.md 5)
actStim,0x004234D0
# Lockdown's action -- expected to ARM a targeted order rather than emit
actLockdown,0x00423F70
# --- the card control's own handlers ------------------------------------------------------
# fxnUpdate the card button's CREATE case binds (0x004596A0: MOV [EAX+0x2E],0x458730)
cardBtnUpdate,0x00458730
# show/hide already known (0x004186A0/0x00418700); these two are the ENABLE and DISABLE
# primitives the layout function picks between on the sign of the condition.
ctrlDisable,0x00418640
ctrlEnable,0x00418E00
