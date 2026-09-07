// sc_unit.h -- the reads of a CUnit and of the dialog tree that every module makes: is
// this pointer a real unit array slot, is that unit still linked into its player's list,
// how long is its build queue, walk the dialog's children.
//
// Everything here is a small, stateless read through sc_engine.h's relocation layer, so
// it is header-only: `static inline`, no sc_unit.cpp, nothing to add to a build list.

#ifndef SC_UNIT_H
#define SC_UNIT_H

#include <windows.h>
#include <stdio.h>

#include "sc_addresses.h"
#include "sc_engine.h"

// ---------------------------------------------------------------------------
// CUnit
// ---------------------------------------------------------------------------

// Is this a pointer to a real slot of the unit array? The array is a fixed 1700-entry
// global, so a valid CUnit* is exactly an in-range, correctly-strided offset from its
// base. EVERY dereference of a unit pointer the game handed us is gated on this -- each
// link of the list walks below included -- or a bad one faults inside the game's thread.
static inline bool ScUnitPtrValid(DWORD unit) {
    if (!unit) return false;
    DWORD arrayBase = ScRuntimeVa(SC_VA_UNIT_ARRAY_BASE);
    if (unit < arrayBase) return false;
    DWORD off = unit - arrayBase;
    if (off % SC_CUNIT_SIZE != 0) return false;
    return (off / SC_CUNIT_SIZE + 1) <= SC_MAX_UNIT_INDEX;   // the wire index is 1-based
}

// index+uniqueness packed exactly as CMDACT_Select and the Right Click / Targeted Order
// builders do it; 0 for anything out of range, which is what the engine encodes too.
static inline WORD ScUnitTag(DWORD unit) {
    if (!ScUnitPtrValid(unit)) return 0;
    DWORD index = (unit - ScRuntimeVa(SC_VA_UNIT_ARRAY_BASE)) / SC_CUNIT_SIZE + 1;
    BYTE uniq = *(BYTE*)(unit + SC_CUNIT_OFF_UNIQUENESS);
    return (WORD)(((WORD)uniq << 11) | (WORD)index);
}

// Reachable from playerUnitList[player] via CUnit+0x6C? Unit (re)init 0x004A0320 links a
// unit in play there and removal 0x004A0740 unlinks it (sc_addresses.h,
// SC_VA_PLAYER_UNIT_LIST, hud-selection-row.md 6.1), so a unit that is NOT reachable has
// been removed, whichever path dropped it. Transport-loaded and mind-controlled units
// stay linked and read as reachable, which is correct: they are live, identity-correct
// units.
// Every link is bounds/stride-validated before it is followed and the walk is bounded, so
// a torn or corrupt list fails closed rather than faulting or hanging.
static inline bool ScUnitInPlayerList(DWORD unit, BYTE player) {
    if (player >= SC_MAX_PLAYERS) return false;
    DWORD head = *(DWORD*)(ScRuntimeVa(SC_VA_PLAYER_UNIT_LIST) + (DWORD)player * 4);
    int n = 0;
    for (DWORD u = head; u && n < SC_MAX_UNITS_WALK; ++n) {
        if (!ScUnitPtrValid(u)) return false;
        if (u == unit) return true;
        u = *(DWORD*)(u + SC_CUNIT_OFF_LIST_NEXT);
    }
    return false;
}

static inline bool ScUnitInOwnPlayerList(DWORD unit) {
    if (!ScUnitPtrValid(unit)) return false;
    return ScUnitInPlayerList(unit, *(BYTE*)(unit + SC_CUNIT_OFF_PLAYER));
}

// Fields of an already-validated unit. Named rather than spelled out as a cast at each
// site, because `*(BYTE*)(u + 0xA5)` is where a wrong offset hides.
static inline BYTE  ScUnitUniqueness(DWORD unit) { return *(BYTE*)(unit + SC_CUNIT_OFF_UNIQUENESS); }
static inline BYTE  ScUnitPlayer(DWORD unit)     { return *(BYTE*)(unit + SC_CUNIT_OFF_PLAYER); }
static inline DWORD ScUnitHitPoints(DWORD unit)  { return *(DWORD*)(unit + SC_CUNIT_OFF_HITPOINTS); }
static inline DWORD ScUnitSprite(DWORD unit)     { return *(DWORD*)(unit + SC_CUNIT_OFF_SPRITE); }

// The one unit this player has selected, or 0 -- 0 for an empty selection AND for a
// selection of two or more, because every caller asks "is there exactly one building to
// talk about".
static inline DWORD ScSoleSelectedUnit(void) {
    DWORD player = *(DWORD*)ScRuntimeAddr(SC_VA_ACTIVE_PLAYER_ID);
    if (player >= SC_MAX_PLAYERS) return 0;
    DWORD* sel = (DWORD*)ScRuntimeAddr(SC_VA_PLAYERS_SELECTIONS) + player * SC_SELECTION_SLOTS;
    DWORD u = sel[0];
    if (!u || sel[1]) return 0;
    return ScUnitPtrValid(u) ? u : 0;
}

// Is the building a plugin record was written against still THAT building, alive?
// Four terms, and each catches something the others miss: the pointer must still be a
// unit-array slot, the slot must not have been recycled (CUnit+0xA5), it must not have
// changed hands, and it must not be a damage death (hitpoints 0, which 0xA5 does not
// catch -- research/selection-circles.md 4.5). `deep` adds the list walk, the only term
// that sees a removal with no damage and no recycle; without it this is four loads.
static inline bool ScUnitRecordLive(DWORD unit, BYTE uniqueness, BYTE player, bool deep) {
    if (!ScUnitPtrValid(unit)) return false;
    if (ScUnitUniqueness(unit) != uniqueness) return false;
    if (ScUnitPlayer(unit) != player) return false;
    if (ScUnitHitPoints(unit) == 0) return false;
    if (deep && !ScUnitInPlayerList(unit, player)) return false;
    return true;
}

// ---------------------------------------------------------------------------
// The engine's five-slot build queue, read and written the way the engine does
// ---------------------------------------------------------------------------

static inline WORD ScUnitQueueSlot(DWORD unit, int slot) {
    return *(WORD*)(unit + SC_CUNIT_OFF_BUILD_QUEUE + (DWORD)slot * 2);
}

static inline void ScUnitSetQueueSlot(DWORD unit, int slot, WORD type) {
    *(WORD*)(unit + SC_CUNIT_OFF_BUILD_QUEUE + (DWORD)slot * 2) = type;
}

// The occupied-slot count. `0xE4` is the empty sentinel every engine reader tests against
// (research/production-queue.md 2.4). The plugin's own overflow is deliberately NOT
// counted here: the engine's five slots and the plugin's queue stay two separate numbers.
static inline int ScUnitQueueLength(DWORD unit) {
    int n = 0;
    for (int i = 0; i < SC_BUILD_QUEUE_SLOTS; ++i) {
        if (ScUnitQueueSlot(unit, i) != SC_BUILD_QUEUE_EMPTY) ++n;
    }
    return n;
}

// ---------------------------------------------------------------------------
// Player resources -- the two counters the engine's own spend and refund move
// ---------------------------------------------------------------------------

static inline DWORD* ScPlayerMinerals(BYTE player) {
    return (DWORD*)(ScRuntimeVa(SC_VA_PLAYER_MINERALS) + (DWORD)player * 4);
}

static inline DWORD* ScPlayerGas(BYTE player) {
    return (DWORD*)(ScRuntimeVa(SC_VA_PLAYER_GAS) + (DWORD)player * 4);
}

// ---------------------------------------------------------------------------
// The BinDialog tree
// ---------------------------------------------------------------------------

static inline DWORD ScDlgChild(DWORD dlg)  { return *(DWORD*)(dlg + SC_BINDLG_OFF_FIRST_CHILD); }
static inline DWORD ScDlgNext(DWORD ctrl)  { return *(DWORD*)(ctrl + SC_BINDLG_OFF_NEXT); }
static inline short ScDlgIndex(DWORD ctrl) { return *(short*)(ctrl + SC_BINDLG_OFF_INDEX); }

// Normalize a dispatcher's argument to the root dialog, the way the engine's own
// layout function does (control -> parent).
static inline DWORD ScDlgRoot(DWORD dialog) {
    if (*(WORD*)(dialog + SC_BINDLG_OFF_TYPE) != 0) {
        return *(DWORD*)(dialog + SC_BINDLG_OFF_PARENT);
    }
    return dialog;
}

// BOUNDED, and that is not paranoia: the log paths run on the OBSERVER thread against
// a list the game thread owns, so a torn `next` has to end the walk rather than spin it.
static inline DWORD ScDlgFindChild(DWORD root, short id) {
    DWORD c = ScDlgChild(root);
    for (int guard = 0; c && guard < SC_MAX_CTRLS_WALK; ++guard, c = ScDlgNext(c)) {
        if (ScDlgIndex(c) == id) return c;
    }
    return 0;
}

// A control's bounds: four shorts at +0x04, in LEFT, TOP, RIGHT, BOTTOM order, and
// RELATIVE TO THE DIALOG -- the engine adds the dialog's own origin (0x00458850 does
// `dlg->rct.left + child->rct.left`), so an absolute point is root + ctrl.
static inline short* ScDlgBounds(DWORD ctrl) { return (short*)(ctrl + SC_BINDLG_OFF_BOUNDS); }

// Fill a plugin-owned control record so the engine treats it as one of its own LSTATIC
// labels: our flags, our (negative, binder-proof) id, the engine's own interact/update
// handlers for the type, and the parent it is about to be linked to. NOT visible -- a
// control that arrives visible is painted by the next redraw walk with an unmeasured rect.
static inline void ScDlgMakeStaticText(DWORD ctrl, DWORD root, short id, const char* text,
                                       DWORD interact, DWORD update) {
    *(DWORD*)(ctrl + SC_BINDLG_OFF_FLAGS)    = SC_CTRL_FONT_SMALLEST;
    *(short*)(ctrl + SC_BINDLG_OFF_INDEX)    = id;
    *(WORD*) (ctrl + SC_BINDLG_OFF_TYPE)     = (WORD)SC_CTRL_TYPE_LSTATIC;
    *(DWORD*)(ctrl + SC_BINDLG_OFF_TEXT)     = (DWORD)(DWORD_PTR)text;
    *(DWORD*)(ctrl + SC_BINDLG_OFF_PARENT)   = root;
    *(DWORD*)(ctrl + SC_BINDLG_OFF_INTERACT) = interact;
    *(DWORD*)(ctrl + SC_BINDLG_OFF_UPDATE)   = update;
    *(DWORD*)(ctrl + SC_BINDLG_OFF_NEXT)     = 0;
}

// Append `ctrl` to `root`'s child chain. false means the chain did not terminate within
// SC_MAX_CTRLS_WALK links and NOTHING was written: the walk is bounded like every other
// walk over a list the game thread owns, so a torn `next` costs one refused splice
// rather than a spin on that thread.
static inline bool ScDlgAppendChild(DWORD root, DWORD ctrl) {
    DWORD tail = ScDlgChild(root);
    if (!tail) {
        *(DWORD*)(root + SC_BINDLG_OFF_FIRST_CHILD) = ctrl;
        return true;
    }
    int guard = 0;
    while (ScDlgNext(tail) && guard < SC_MAX_CTRLS_WALK) { tail = ScDlgNext(tail); ++guard; }
    if (ScDlgNext(tail)) return false;
    *(DWORD*)(tail + SC_BINDLG_OFF_NEXT) = ctrl;
    return true;
}

// The engine's own default interact/update handler for a control type, out of the two
// tables it dispatches through. Both are non-zero on a build that really draws the type;
// a null in either is evidence that this build does not dispatch it the way the table
// dump says, and both callers refuse to splice rather than hand over an undrawable one.
static inline void ScDlgDefaultHandlers(int ctrlType, DWORD* interact, DWORD* update) {
    *interact = *(DWORD*)(ScRuntimeVa(SC_VA_DEFAULT_INTERACT_TABLE) + (DWORD)ctrlType * 4);
    *update   = *(DWORD*)(ScRuntimeVa(SC_VA_DEFAULT_UPDATE_TABLE)   + (DWORD)ctrlType * 4);
}

// Unlink a control we spliced in. Every link is probed before it is followed: this runs
// on the detach path, where the dialog may already be gone. A control that is not in the
// chain is left alone -- no return value, because a caller could do nothing differently.
static inline void ScDlgRemoveChild(DWORD root, DWORD ctrl) {
    DWORD* link = (DWORD*)(root + SC_BINDLG_OFF_FIRST_CHILD);
    while (*link && *link != ctrl) {
        if (!ScReadable(*link + SC_BINDLG_OFF_NEXT, 4)) return;
        link = (DWORD*)(*link + SC_BINDLG_OFF_NEXT);
    }
    if (*link == ctrl) *link = ScDlgNext(ctrl);
}

// The engine's five ring slots as "0x000,0x0E4,..." for a log line; truncates rather than
// overruns the caller's buffer.
static inline int ScUnitFormatQueue(DWORD unit, char* out, int outLen) {
    int used = 0;
    out[0] = '\0';
    for (int s = 0; s < SC_BUILD_QUEUE_SLOTS && used + 8 < outLen; ++s) {
        used += _snprintf(out + used, outLen - used, "%s0x%03X",
                          s ? "," : "", (unsigned)ScUnitQueueSlot(unit, s));
    }
    return used;
}

// CreateNewUnitSelections (0x0049AE40): EAX = the CUnit* list, count PUSHED. The count is
// a memory operand rather than a register because the callee reads it ESP-relative, and
// an ESP-relative operand would be four bytes off if GCC had spilled it.
static inline void ScCreateSelections(DWORD* list, int count) {
    void* fn = ScRuntimeAddr(SC_VA_CREATE_NEW_UNIT_SELECTIONS);
    __asm__ __volatile__("pushl %[n]\n\t"
                         "calll *%[fn]"
                         : "+a"(list)
                         : [n] "m"(count), [fn] "r"(fn)
                         : "ecx", "edx", "cc", "memory");
}

static inline DWORD ScStatDialog(void)   { return *(DWORD*)ScRuntimeAddr(SC_VA_STATDATA_DIALOG); }
static inline DWORD ScPortraitUnit(void) { return *(DWORD*)ScRuntimeAddr(SC_VA_ACTIVE_PORTRAIT_UNIT); }

// ---------------------------------------------------------------------------
// The engine's three control primitives
//
// 0x004186A0 / 0x00418700 take the control in ESI (GPTP unit_stat_selection.cpp
// helpers; our decompile of 0x00425960 shows the same register use) and 0x0041C400
// takes it in EAX. VC6 callee-saved rules preserve EBX/ESI/EDI across the call.
// ---------------------------------------------------------------------------

// A test stand-in for one of the three primitives below, so a module's own logic can run
// with no engine under it.
typedef void (*ScCtrlFn)(DWORD ctrl);

static inline void ScCtrlShow(DWORD ctrl) {
    void* fn = ScRuntimeAddr(SC_VA_SHOW_CONTROL);
    __asm__ __volatile__("calll *%[fn]"
        : : "S"(ctrl), [fn] "r"(fn) : "eax", "ecx", "edx", "cc", "memory");
}

static inline void ScCtrlHide(DWORD ctrl) {
    void* fn = ScRuntimeAddr(SC_VA_HIDE_CONTROL);
    __asm__ __volatile__("calll *%[fn]"
        : : "S"(ctrl), [fn] "r"(fn) : "eax", "ecx", "edx", "cc", "memory");
}

static inline void ScCtrlUpdate(DWORD ctrl) {
    void* fn = ScRuntimeAddr(SC_VA_UPDATE_CONTROL);
    DWORD inout = ctrl;
    __asm__ __volatile__("calll *%[fn]"
        : "+a"(inout) : [fn] "r"(fn) : "ecx", "edx", "cc", "memory");
}

// The same three, through `seam` when a test installed one. NULL means "call the
// engine", which is what the shipped plugin always passes.
static inline void ScCtrlShowVia(ScCtrlFn seam, DWORD ctrl) {
    if (seam) seam(ctrl); else ScCtrlShow(ctrl);
}
static inline void ScCtrlHideVia(ScCtrlFn seam, DWORD ctrl) {
    if (seam) seam(ctrl); else ScCtrlHide(ctrl);
}
static inline void ScCtrlUpdateVia(ScCtrlFn seam, DWORD ctrl) {
    if (seam) seam(ctrl); else ScCtrlUpdate(ctrl);
}

#endif // SC_UNIT_H
