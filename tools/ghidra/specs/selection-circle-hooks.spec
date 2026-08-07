# Task 014 hook/call targets for the selection-circle change.
#
# label,addrHex
#
# HookProbe emits, per address: the whole function's disassembly with raw bytes and a
# PC-relative flag per instruction, the detour patch window (whole instructions covering 5
# bytes), and every caller. The plugin needs all three: the prologue bytes go into the
# install-time signature check, the patch size goes into ScHookInstall, and the caller list is
# how "is this really the only path in" gets answered instead of assumed.

# --- the one function we need to HOOK ---------------------------------------------------------
# CreateNewUnitSelectionsFromList: the client-side "the selection just changed" point. It
# detaches the graphics of every unit in activePlayerSelection and attaches them to the new
# list, so hooking its ENTRY is the one place a plugin can drop its own extra circles BEFORE the
# engine re-attaches -- which keeps the two sets disjoint at all times.
CreateNewUnitSelectionsFromList,0x0049AE40

# --- the engine primitives we CALL (never hooked; called through a function pointer) ----------
# Sprite::AddSelectionCircleOverlay -- EAX = CSprite*, args (colorByte, baseImageId 0x231).
# FUN_004D6810 shows it lands the image at 0x231 + spritesDatCircleIndex[sprite_id], i.e. in
# 0x231..0x23A, with drawfunc 0x0D.
spriteAddOverlayTop,0x004D7070
# Sprite::RemoveSelectionCircle -- ECX = CSprite*. Clears flag 0x01 and frees the 0x231..0x23A
# image. This is the invincible-unit deselect path, and it is exactly "remove the circle and
# nothing else", which is what a plugin that never sets the `selected` bit needs.
spriteRemoveSelectionCircle,0x004975D0

# --- for the record: the two primitives the engine itself uses -------------------------------
unitSelectGraphics,0x004E6180
unitDeselectGraphics,0x004E6290
spriteSelect,0x004997A0
