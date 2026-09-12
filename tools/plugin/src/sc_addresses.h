// sc_addresses.h -- StarCraft 1.16.1 selection-subsystem static addresses.
//
// Every constant here is a *preferred-image-base* virtual address (StarCraft.exe's
// PE ImageBase is 0x00400000, see research/pe-anatomy.md). Nothing dereferences these
// directly: the plugin converts each one to a runtime address with
//
//     runtime = actualModuleBase + (staticVA - SC_PREFERRED_IMAGE_BASE)
//
// so a relocated/ASLR'd load is handled rather than assumed away.
//
// Provenance is research/binary-selection-map.md, quoted section by section in the
// comment above each constant, with per-instruction rows in the committed evidence
// table research/data/selection-xrefs.tsv. Every block below is derived from this
// binary rather than inherited from prior art, except where a comment says otherwise.

#ifndef SC_ADDRESSES_H
#define SC_ADDRESSES_H

#include <windows.h>

// PE ImageBase of StarCraft.exe 1.16.1 (research/pe-anatomy.md).
#define SC_PREFERRED_IMAGE_BASE 0x00400000u

// ---------------------------------------------------------------------------
// Selection state (research/binary-selection-map.md)
// ---------------------------------------------------------------------------

// CUnit*[12] -- the client's own selection. binary-selection-map.md 2.1: 119
// referencing instructions across 52 functions, element offsets 0..44, none beyond.
#define SC_VA_CLIENT_SELECTION_GROUP 0x00597208u

// u8 -- how many of those 12 slots are filled. binary-selection-map.md 7.2:
// 23 accesses, every one byte-width.
#define SC_VA_CLIENT_SELECTION_COUNT 0x0059723Du

// CUnit*[12] -- second client selection array. binary-selection-map.md 3.2.
#define SC_VA_CLIENT_SELECTION_GROUP2 0x0059724Cu

// CUnit*[12] -- the active player's selection; abuts playersSelections exactly
// (0x006284B8 + 12*4 == 0x006284E8, binary-selection-map.md 3.3).
#define SC_VA_ACTIVE_PLAYER_SELECTION 0x006284B8u

// CUnit*[8][12] -- per-player selections. binary-selection-map.md 3.4.
#define SC_VA_PLAYERS_SELECTIONS 0x006284E8u

// u8 -- selection iterator. binary-selection-map.md 2.1 (41 instructions).
#define SC_VA_SELECTION_ITERATOR 0x006284B6u

// Active player id, from binary-selection-map.md 7's prose alone -- these three have no
// rows in selection-xrefs.tsv. Note 7 there warns that THREE distinct player-id globals
// are in play and conflating them produces bugs, so the plugin logs all three.
#define SC_VA_ACTIVE_PLAYER_ID    0x0051267Cu  // named by selection-cap.md 2.2
#define SC_VA_PLAYER_ID_512688    0x00512688u  // used in selectSingleUnitFromID
#define SC_VA_PLAYER_ID_512678    0x00512678u  // GPTP ACTIVE_NATION_ID

#define SC_SELECTION_SLOTS 12
#define SC_MAX_PLAYERS     8

// ---------------------------------------------------------------------------
// CONTROL GROUPS. Full evidence, with decompiles, in research/control-groups.md;
// the committed instruction table is research/data/hotkey-xrefs.tsv.
// ---------------------------------------------------------------------------

// u32[8][18][12] -- the control-group store, holding StoredUnit TAGS
// ((uniqueness << 11) | unitIndex), not CUnit*. Shape confirmed twice over in
// binary-selection-map.md 3.5 and again by hotkeySaveOrAdd's own row arithmetic,
// `(group + activePlayerId*0x12) * 0xc` dwords off this base (0x004965E9).
//
// Groups 0..9 are the Ctrl+N groups; 10..17 are the engine's OWN alt-click
// recent-selection ring (binary-selection-map.md 5.2). The plugin mirrors 0..9,
// never touches 10..17, and only ever READS this array.
#define SC_VA_SELECTION_HOTKEYS 0x0057FE60u
#define SC_HOTKEY_GROUPS_PER_PLAYER 18
#define SC_HOTKEY_SLOTS_PER_GROUP   12

// u16[8][8] -- when each recent-selection slot was last used, the LRU key 0x00496560
// scans backwards over. Cleared beside the hotkey array by both resets. Not read here.
#define SC_VA_RECENT_SELECTION_TIMES 0x0063FE40u

// The two globals implementing 500 ms double-tap-to-centre, immediately behind
// clientSelectionGroup2 (binary-selection-map.md 3.2). Every 0x13-emitting site in
// the key dispatcher writes 0xFF to the group id. Not read or written here.
#define SC_VA_LAST_HOTKEY_TAP_TIME 0x0059727Cu
#define SC_VA_LAST_HOTKEY_GROUP_ID 0x00597280u

// Wire command 0x13 is three bytes: id, action, group -- built at 0x004C07BF
// (`MOV byte ptr [EBP-4],0x13` / `[EBP-3],AL` / `[EBP-2],BL`). The action values are
// the cases CMDRECV_Hotkey (0x004C2870) dispatches on.
#define SC_HOTKEY_CMD_BYTES 3

// The action values, from CMDRECV_Hotkey's own dispatch (0x004C2870):
//   [+1]==0 -> 0x004965D0(1)  clear the group's 12 slots, then fill  = ASSIGN (Ctrl+N)
//   [+1]==1 -> 0x00496940(g)                                          = RECALL (N)
//   [+1]==2 -> 0x004965D0(0)  append at the first free slot, dedup    = ADD
// The key dispatcher 0x004846E0 carries three families of ten sites, one per action: ten
// `13 00 g` (shared tail 0x004849EB), ten inline `13 02 g`, ten recall sites (0x00496B40).
#define SC_HOTKEY_ASSIGN 0
#define SC_HOTKEY_RECALL 1
#define SC_HOTKEY_ADD    2

// The engine's own functions on this path. NOT hooked or called by this plugin;
// recorded because every claim the code makes about ordering names one of them.
#define SC_VA_HOTKEY_CLEAR            0x004965A0u  // REP STOSD over both arrays
#define SC_VA_HOTKEY_SAVE_OR_ADD      0x004965D0u  // the store; arg 0 = add, 1 = assign
#define SC_VA_HOTKEY_DOUBLE_TAP       0x004967E0u  // centre the view on a re-tap
#define SC_VA_HOTKEY_RECALL_RECV      0x00496940u  // receive side: writes playersSelections
#define SC_VA_HOTKEY_KEY_HANDLER      0x00496B40u  // client side: 0x0049AE40 then CMDACT_HotkeyUnit
#define SC_VA_CMDACT_HOTKEY_UNIT      0x004C07B0u  // builds and queues the 3-byte 0x13
#define SC_VA_CMDRECV_HOTKEY          0x004C2870u  // action dispatch, group guard `CMP AL,0x12`
#define SC_VA_GAME_START_HOTKEY_CLEAR 0x004EEC30u  // the game-start reset

// ---------------------------------------------------------------------------
// Game start / save load -- the GAME-SESSION EPOCH's clock. The call graph these three
// sit in, with the caller COUNT beside each, taken by scanning every E8/E9 rel32 in
// .text rather than from a decompiler's xref list:
//
//   0x004EF100  startGame                     1 caller  (0x004E071B)
//     0x004EF27A  call gameStartClear         1 caller  <- the epoch bumps here
//     0x004EF32B  call startOrLoadGame        1 caller
//                   0x004EED48  call loadSavedGame   1 caller  <- the save is read here
//
// One caller each is what makes the ordering a PROOF rather than an observation: a save
// cannot be deserialised except through a chain that has already run the bump.
// sc_session.h states it in full, with the early returns that do not affect it.
#define SC_VA_START_GAME              0x004EF100u  // the whole game, entered once per game
#define SC_VA_START_OR_LOAD_GAME      0x004EED10u  // clears playersSelections, then loads
#define SC_VA_LOAD_SAVED_GAME         0x004CFEF0u  // reads the save file; the LOAD WITNESS

// Where the epoch's detour is spliced: gameStartClear + 7, `MOV EAX,0xFFFF`, one whole
// instruction of exactly five bytes with no PC-relative operand. The function's own
// first five bytes span `CALL 0x0049BB90`, which sc_hook.cpp copies verbatim and
// therefore cannot relocate.
#define SC_VA_GAME_START_EPOCH_SITE   0x004EEC37u

// The Load Game path's heap buffer for the save it is about to read. Non-zero exactly
// while a load is pending: gameStartClear itself branches on it (0x004EEC62, skipping
// the hotkey clear), and startGame's caller frees and zeroes it on the way out
// (0x004E07D5). READ ONLY, and only so a log line can say which kind of start this was.
#define SC_VA_PENDING_SAVE_NAME       0x006D1218u

// ---------------------------------------------------------------------------
// CUnit layout. Offsets inherited from GPTP; each is USED by a decompiled
// instruction here, which is corroboration rather than independent derivation
// (binary-selection-map.md 8 "Inherited and used as-is" makes the same caveat).
// ---------------------------------------------------------------------------

#define SC_CUNIT_SIZE            0x150u  // 336; measured live in
                                         // research/runtime-selection-observations.md 3.5
#define SC_CUNIT_OFF_SPRITE      0x0Cu   // CSprite*; read as [unit+0x0C] by every function
                                         // in research/selection-circles.md 2
#define SC_CUNIT_OFF_PLAYER      0x4Cu   // u8 owning player
#define SC_CUNIT_OFF_UNIT_ID     0x64u   // u16 unit type id
#define SC_CUNIT_OFF_UNIQUENESS  0xA5u   // u8, the tag's staleness check

// u8 -- the unit's CURRENT (main) ORDER id, immediately after the owning player at 0x4C.
// Derived from the receive-side handlers in this binary, which read it to avoid
// re-issuing an order a unit is already on: the 0x25 handler (0x004C1F10) issues order
// 0x63 and skips a unit whose [+0x4D] is already 0x63; 0x26 (0x004C1E80) does the same
// with 0x62; 0x2C (0x004C1FA0) with 0x74. THIS is the field that changes when a unit is
// told to move, stop or hold.
#define SC_CUNIT_OFF_ORDER_ID    0x4Du

// u8 -- the SECONDARY order id, which runs alongside the main one. The 0x22 handler
// (0x004C0660) sets it to 0x6E and clears the order-target fields beside it, and
// 0x00491B30 (from the 0x21 handler) sets it to 0x6D after deducting the unit's energy
// -- a cloak, which persists while a unit does something else. Logged next to the main
// order so a command that changes only one of the two is still visible.
#define SC_CUNIT_OFF_ORDER2_ID   0xA6u

// u32 -- unit flags. Bit 0x10 is the burrowed/submerged state: the Stop handler
// (0x004C2190) refuses a unit with it set unless the unit's type is 0x67, the one type
// that acts while burrowed, and the Right Click applier (0x004560D0) picks a different
// behaviour table for exactly that combination. READ ONLY, same as the order id.
#define SC_CUNIT_OFF_FLAGS       0xDCu
#define SC_UNIT_FLAG_BURROWED    0x10u
// Bit 0x01 is COMPLETED, and it matters to anything that counts units out of the player's
// unit list: a unit still being trained is ALREADY LINKED INTO THAT LIST. Measured, the
// same unit type twice in one log:
//   in progress  type=0x007 hp=13484 flags=0x00130000
//   finished     type=0x007 hp=15360 flags=0x00130001
// -- HP ramping up towards the SCV's 60 (15360 in the engine's 1/256) with the bit clear,
// and the bit set once it is at maximum. So "how many SCVs exist" is not "how many have
// been built": a guard that counts list members to prove nothing FINISHED counts an
// under-construction unit and fails on a good fixture.
#define SC_UNIT_FLAG_COMPLETED   0x01u

// u16 -- the unit's ENERGY, in the engine's 1/256 fixed point (a 200-energy caster
// reads 0xC800). Named from 0x00491B30, the deduct the 0x21 handler calls, by reading
// that function's own instructions rather than inheriting the claim:
// it compares `(u16)(cost * 0x100) <= *(u16*)(unit + 0xA2)` and then does
// `*(short*)(unit + 0xA2) += cost * -0x100`. A field compared against a cost and then
// reduced by exactly that cost is the resource the ability spends.
// research/ability-semantics.md 3.
#define SC_CUNIT_OFF_ENERGY      0xA2u

// u8 -- the STIM TIMER, in game frames. Derived from the 0x36 handler 0x004C2F30 in
// THIS binary (research/ability-semantics.md 2, which quotes the disassembly): it
// writes 0x25 at 0x004C2FEC unless the field already reads >= 0x25, i.e. a fixed
// duration refreshed rather than stacked, written immediately after the unit pays the
// ability's HP cost. 16 instructions in the whole binary touch this displacement, and
// the corroborating pair 0x00492F70 reads it, decrements and writes it back -- it ticks
// down. READ ONLY here.
#define SC_CUNIT_OFF_STIM_TIMER  0x115u
#define SC_STIM_TIMER_FRAMES     0x25u   // what 0x004C2F30 writes

// ---------------------------------------------------------------------------
// SELECTION CIRCLES. Full evidence, with disassembly, in
// research/selection-circles.md.
//
// NOTE the offsets below are NOT the ones BWAPI's CSprite.h publishes. BWAPI puts
// selectionIndex at 0x03 and flags at 0x06; this binary uses 0x0B and 0x0E, because
// its CSprite begins with the two linked-list pointers. Both are read off
// instructions in this binary rather than inherited.
// ---------------------------------------------------------------------------

#define SC_CSPRITE_OFF_SELECTION_INDEX 0x0Bu  // u8; written at 0x004E61D6 / 0x004E61FD
#define SC_CSPRITE_OFF_FLAGS           0x0Eu  // u8; tested at 0x004E61A3, 0x004975D3, ...
// u16 map-pixel position. 0x0049F860 passes the pair as (x, y) to 0x00469F60
// (`FUN_00469f60(*(u16*)(sprite+0x14), *(u16*)(sprite+0x16))`), and 0x0046F3A0 uses
// [sprite+0x16] alone as the y in its draw-order comparison.
#define SC_CSPRITE_OFF_POS_X           0x14u
#define SC_CSPRITE_OFF_POS_Y           0x16u
#define SC_CSPRITE_OFF_MAIN_IMAGE      0x18u
#define SC_CSPRITE_OFF_FIRST_OVERLAY   0x1Cu
#define SC_CSPRITE_OFF_LAST_OVERLAY    0x20u

// The viewport's top-left corner in MAP pixels, so client = map - these. Both are read
// by the click handler at 0x0046FB40, which builds the rectangle it searches as
// `{ left, top, left + 0x280, top + 400 }`. Used only to log where a circled unit is on
// screen so an automated test can aim a click at one; no feature depends on them.
#define SC_VA_SCREEN_LEFT 0x0062848Cu  // u16 (the binary reads the low half)
#define SC_VA_SCREEN_TOP  0x006284A8u  // u16

// Sprite flag bits, confirmed against this binary (selection-circles.md 3):
//   0x01 -- a selection-circle image (id 0x231..0x23A) is attached to this sprite.
//           0x004975D0 clears exactly this bit and frees exactly that image.
//   0x08 -- "selected", set with selectionIndex by 0x004E6180, cleared by 0x00497620.
//           IT IS THE GATE ON ALL FOUR selectionIndex READS IN THE BINARY: 0x0046FD77
//           and 0x0049F7B3 use the value as a memmove offset into a 12-entry STACK array
//           (no value is safe there for a unit outside the engine's 12), and 0x0049F00B
//           and 0x0049F8B6 save it and re-attach. Leaving this bit clear is what keeps
//           plugin-circled units out of reach of all four (selection-circles.md 4).
#define SC_SPRITE_FLAG_SEL_CIRCLE 0x01u
#define SC_SPRITE_FLAG_SELECTED   0x08u

// u8[8], indexed by CUnit+0x4C. 0x004E61A6 reads `MOV DL,byte ptr [ECX + 0x581d6a]`
// with ECX = the owning player, and passes the byte straight to the overlay builder,
// which stores it at image+0x30 (the colour-remap selector, 0x004D6810).
#define SC_VA_SELECTION_COLOR_TABLE 0x00581D6Au

// Base image id for the selection circle. 0x004D6810 computes the real id as
// `0x231 + spritesDatCircleIndex[sprite->sprite_id]`, and the remover accepts
// 0x231..0x23A -- ten consecutive ids, the ten circle sizes.
#define SC_SELECTION_CIRCLE_IMAGE_BASE 0x231u

// EAX = CSprite*, __stdcall(u32 colourByte, u32 baseImageId), RET 8. Allocates an
// image from the free list, links it at the sprite's LAST-overlay end (CSprite+0x20)
// and initialises it through 0x004D6810. Returns the new CImage* or NULL when the
// image free list is empty. Call site: 0x004E61B4-0x004E61BC.
//
// WHICH END OF THE LIST DRAWS FIRST IS NOT ESTABLISHED, so do not assume the link end
// controls draw order: the circle renders UNDER the unit while the health bar (linked
// at the FIRST-overlay end by 0x004D6420) renders over it, and nothing has decompiled
// the renderer's walk (research/selection-circles.md 7). Settle it before relying on it.
#define SC_VA_SPRITE_ADD_SEL_CIRCLE 0x004D7070u

// ECX = CSprite*, no stack arguments, RET. If flag 0x01 is set, clears it, finds the
// image whose id is in 0x231..0x23A and frees it. This is the engine's own
// remove-just-the-circle primitive (it is the whole of the invincible-unit deselect
// path), which is exactly what a plugin that never sets flag 0x08 needs.
#define SC_VA_SPRITE_REMOVE_SEL_CIRCLE 0x004975D0u

// EAX = CUnit**, __stdcall(u32 count), RET 4. The client-side "replace the whole
// selection" funnel: it detaches the selection graphics of every unit in
// activePlayerSelection, then attaches them to the new list. 10 callers covering the
// drag box, every click path and control-group recall -- which makes its ENTRY the one
// place a plugin can drop its own extra circles before the engine re-attaches.
#define SC_VA_CREATE_NEW_UNIT_SELECTIONS 0x0049AE40u

// The engine's own per-unit primitives. NOT called or hooked by this plugin; listed
// because research/selection-circles.md 2 quotes them, and an HP bar would need them.
#define SC_VA_UNIT_SELECT_GRAPHICS   0x004E6180u  // EAX = CUnit*, __stdcall(u8 slot)
#define SC_VA_UNIT_DESELECT_GRAPHICS 0x004E6290u  // EAX = CUnit*

// ---------------------------------------------------------------------------
// COMMAND PATH. Full evidence, with disassembly, in research/command-path.md.
// ---------------------------------------------------------------------------

// __fastcall(ECX = const void* cmdBytes, EDX = size_t len) -- appends one command
// to the outgoing turn buffer. THE funnel: every CMDACT_* builder in the binary
// reaches the wire through this one function (117 references). It flushes through
// 0x00485A40 when the command would not fit. command-path.md 1.
#define SC_VA_QUEUE_COMMAND 0x00485BD0u

// The turn buffer queueCommand appends into, and its running byte count. Inherited from
// BWAPI Offsets.h:75-76 and re-confirmed by queueCommand's own copy destination
// (`&DAT_00654880 + DAT_00654aa0`). command-path.md 1.
#define SC_VA_TURN_BUFFER          0x00654880u
#define SC_VA_BYTES_IN_CMD_QUEUE   0x00654AA0u  // u32
#define SC_VA_MAX_CMD_QUEUE_BYTES  0x0057F0D8u  // u32; queueCommand's own bound

// __stdcall(u32 count, CUnit** units) -- the client's selection commit point.
// Builds the 0x09/0x0A/0x0B wire commands from `units` and queues each.
// Hooking it is how the plugin learns the engine's (truncated) new selection at
// the exact moment it is committed. binary-selection-map.md 6.3, command-path.md 2.
#define SC_VA_CMDACT_SELECT 0x004C0860u

// __stdcall(CUnit** candidates, CUnit** out12, CUnit* clicked) -> u32 count
// Builds the drag-box / ctrl-click selection. `candidates` is NULL-terminated and
// is NOT capped; the 12-cap is the `if (n < 0xC)` at 0x0046F206 inside it.
// selection-cap.md 4.1, command-path.md 3.
#define SC_VA_SORT_ALL_UNITS 0x0046F0F0u

// ---------------------------------------------------------------------------
// THE BOX-SELECT BUILDING GATE. Full evidence, with both listings, in
// research/building-groups.md.
// ---------------------------------------------------------------------------

// ECX = CUnit*, no stack arguments, returns EAX (0/1), RET. THE multi-select gate: the
// reason a drag box over six Supply Depots selects one of them. BOTH sides of the
// selection path call it, and each call is a separate gate:
//   client  SortAllUnits 0x0046F0F0, `CALL 0x0047b770` at 0x0046F1A3 -- a unit that
//           fails is never stored in out12; the tail substitutes that ONE remembered
//           unit and returns a count of 1 when nothing else was accepted.
//   sim     addUnitToSelectionSlot 0x0049AF80, `CALL 0x0047b770` at 0x0049AF9D, reached
//           only when the slot (EBX) is > 0 -- slot 0 takes anything, later slots pass.
//
// The predicate, decompiled (answering selection-cap.md 8 q9): it FAILS on
// unitsDatFlags[unitId] & 0x01 (Building) or & 0x800, on CUnit+0xDC & 0x400, on a
// non-zero CUnit+0x117 / +0x119 / +0x124, and on unit ids 0x0D, 0x24, 0x59, 0x5A,
// 0x5D..0x60, 0x69, 0xCA and 0xCB..0xD5.
//
// The plugin CALLS it (read-only) and never patches it: it is the engine's own answer to
// "may this unit share a selection", and a re-implementation would be a second copy.
#define SC_VA_UNIT_IS_STANDARD_AND_MOVABLE 0x0047B770u

// u32[], indexed by the unit TYPE id (CUnit+0x64) -- units.dat's unit-prototype flags.
// Both selection functions index it the same way: `TEST byte ptr [ECX*0x4 + 0x664080],
// 0x10` at 0x0046F138 (the subunit flag, which makes SortAllUnits follow CUnit+0x70 to
// the parent) and `DAT_00664080 + unitId*4` inside 0x0047B770. Bit 0x01 is what makes a
// building fail the gate; the plugin only READS it, so a run's evidence says WHICH bit
// refused the unit rather than asserting the table's identity.
#define SC_VA_UNITS_DAT_FLAGS 0x00664080u
#define SC_UNITSDAT_FLAG_BUILDING      0x00000001u
#define SC_UNITSDAT_FLAG_SINGLE_ENTITY 0x00000800u

// A building's RALLY POINT, written by the Right Click applier 0x004560D0 in the
// branch its per-type behaviour table selects for a building (the `0x27` case):
//     *(int*)(unit + 0xFC) = target ? target : unit;
//     *(u16*)(unit + 0xF8) = target->sprite->x;      // CSprite+0x14
//     *(u16*)(unit + 0xFA) = target->sprite->y;      // CSprite+0x16
// READ ONLY here. This is the in-process oracle for "the order reached this building":
// a rally is the one order a building accepts from a plain right-click, and it lands in
// fields the plugin can read back per unit.
#define SC_CUNIT_OFF_RALLY_X    0xF8u
#define SC_CUNIT_OFF_RALLY_Y    0xFAu
#define SC_CUNIT_OFF_RALLY_UNIT 0xFCu

// Mixed convention: EAX = current count, ECX = CUnit** out12, stack [+4] = CUnit* unit,
// [+8] = CUnit* clicked, RET 8. Called once for EVERY unit that passed all selection
// filters but did not fit in the 12 slots -- the one place in the engine where the units
// the cap is about to discard are individually visible. command-path.md 3.
#define SC_VA_SORT_OVERFLOW 0x0046F040u

// Unit-tag encoding, read off three independent instruction sequences in this binary
// (CMDACT_Select 0x004C0919, the Right Click builder 0x004C03A0, the Targeted Order
// builder 0x004C0323 -- all three compute it identically):
//     index = (unitPtr - 0x0059CCA8) / 0x150 + 1        // 1-based
//     if (index > 0x6A4) tag = 0                        // CMP ECX,0x6a4 / JBE
//     else tag = (unit[0xA5] << 11) | index
// The base 0x0059CCA8 is unverified prior art in
// research/runtime-selection-observations.md 3.5; here it is off the binary itself.
#define SC_VA_UNIT_ARRAY_BASE 0x0059CCA8u
#define SC_MAX_UNIT_INDEX     0x6A4u   // inclusive; index 0 and >0x6A4 encode as tag 0

// Wire command ids used by the fan-out; the full 46-entry table is command-path.md 5.
#define SC_CMD_SELECT        0x09u
#define SC_CMD_SELECT_ADD    0x0Au
#define SC_CMD_SELECT_REMOVE 0x0Bu
#define SC_CMD_HOTKEY        0x13u
#define SC_CMD_RIGHT_CLICK   0x14u
#define SC_CMD_TARGETED_ORDER 0x15u

// ---------------------------------------------------------------------------
// HUD SELECTION ROW. Full evidence, with decompiles and the creation chain, in
// research/hud-selection-row.md; committed instruction tables in
// research/data/hud-*.tsv.
// ---------------------------------------------------------------------------

// No arguments, returns void. THE per-frame status-area dispatcher: the single entry
// the HUD driver 0x004D93F0 calls each frame, branching portrait-null / single-unit /
// multi-select (hud-selection-row.md 4.2). sc_hudrow detours THIS (not the multi-select
// act/cond pair) so it can restore the row to stock even when a shadow click drops the
// selection to one unit and the engine takes its single branch. Patch window 5 bytes /
// 1 instruction (MOV EAX,[0x00597248]), reloc-safe; one caller.
#define SC_VA_STAT_DATA_UPDATE 0x00458120u

// The multi-select layout ("act") and refresh-condition ("cond") the dispatcher calls;
// sc_hudrow re-implements their effect for a page rather than detouring them
// (hud-selection-row.md 4.2).
#define SC_VA_UNITSTAT_ACT_SELECTION  0x00425960u
#define SC_VA_UNITSTAT_COND_SELECTION 0x00424660u

// Unit* -- the active portrait unit; the dispatcher's first test (portrait NULL ->
// hide the whole status area). sc_hudrow reads it to decide whether to page.
#define SC_VA_ACTIVE_PORTRAIT_UNIT 0x00597248u

// Generic dialog primitives (GPTP helpers; conventions verified against this binary):
#define SC_VA_SHOW_CONTROL   0x004186A0u  // ESI = BinDlg*
#define SC_VA_HIDE_CONTROL   0x00418700u  // ESI = BinDlg*
#define SC_VA_UPDATE_CONTROL 0x0041C400u  // EAX = BinDlg*
// ESI = BinDlg*. Clears SC_CTRL_FLAG_DISABLED, sends the control its enable event and
// marks it for update; a NO-OP when the bit is already clear. The call queueLayout's
// occupied branch makes (0x00426A33..0x00426A55) and the research layouts make for their
// own icon (0x00426500, 0x004266F0).
#define SC_VA_ENABLE_CONTROL 0x00418E00u

// __fastcall(ECX = BinDlg* control, EDX = event) -> int. The wireframe button's interact
// handler; all 12 buttons point here via the 44-entry table at 0x00504AF0
// (hud-selection-row.md 3). sc_hudrow WRAPS the per-control pointer (control+0x2A) with a
// thin shim and tail-calls this address -- the code itself is never patched.
#define SC_VA_WIREFRAME_BTN_INTERACT 0x004583E0u

// The statdata module's globals (hud-selection-row.md 2):
#define SC_VA_STATDATA_DIALOG 0x0068C1F0u  // BinDlg* -- the whole status-area dialog
#define SC_VA_STAT_DIRTY      0x0068C1F8u  // u8 -- redraw-needed flag the dispatcher consumes
// u8 -- which LAYOUT the pane currently holds. Every layout of the per-unit-type act
// 0x00427890 compares it before doing anything to the child list and hides every child
// (0x00457310, from id -8 on) ONLY when it differs, then writes its own value: 3 the
// default single-unit layout, 4 a foreign player's unit, 7 the tech-research layout
// (0x004266F0), 8 the upgrade-research layout (0x00426500); the dispatcher 0x00458120
// zeroes it when the pane empties. So a control this plugin shows in a research layout
// stays shown until the KIND changes, not until the next frame.
#define SC_VA_STAT_ALL_HIDDEN 0x0068C1E5u
#define SC_STAT_LAYOUT_TECH    7
#define SC_STAT_LAYOUT_UPGRADE 8

// Default per-control-type handler tables the .bin relocator (0x004194E0) assigns from;
// sc_hudrow's indicator takes its handlers from the same tables, so it is drawn by
// exactly the code a loaded control would be.
#define SC_VA_DEFAULT_INTERACT_TABLE 0x005014ACu
#define SC_VA_DEFAULT_UPDATE_TABLE   0x00501504u

// BinDlg field offsets. Those marked "hud 2" are proven by an instruction cited
// in hud-selection-row.md 2 (read out of THIS binary). Those marked "GPTP" are
// inherited from GPTP SCBW/structures.h and used as-is, NOT independently re-derived.
#define SC_BINDLG_OFF_NEXT        0x00u   // hud 2 (every child walk)
#define SC_BINDLG_OFF_BOUNDS      0x04u   // GPTP (rct); s16 left,top,right,bottom.
                                          //   Used only to POSITION the indicator and
                                          //   to log button rects -- a wrong offset
                                          //   mis-aims a diagnostic, never mis-selects.
#define SC_BINDLG_OFF_TEXT        0x14u   // hud 2 (relocator 0x004194E0 fixes pszText)
#define SC_BINDLG_OFF_FLAGS       0x18u   // hud 2 (0x0045845D TEST [ctrl+0x18],0x8)
#define SC_BINDLG_OFF_INDEX       0x20u   // hud 2 (layout walk compares [ctrl+0x20]==0x21)
#define SC_BINDLG_OFF_TYPE        0x22u   // hud 2 ("is this the root" test); 0 = dialog
#define SC_BINDLG_OFF_GRAPHIC     0x24u   // hud 2 (wireframe draw writes border id here)
#define SC_BINDLG_OFF_USER        0x26u   // hud 2 (button CREATE allocs 8B into +0x26)
#define SC_BINDLG_OFF_INTERACT    0x2Au   // hud 2 (0x00418EB0 calls [ctrl+0x2A])
#define SC_BINDLG_OFF_UPDATE      0x2Eu   // hud 2 (0x0045841C MOV [ESI+0x2E],0x456F50)
#define SC_BINDLG_OFF_PARENT      0x32u   // hud 2 (click handler climbs [ctrl+0x32])
#define SC_BINDLG_OFF_FIRST_CHILD 0x42u   // hud 2 (every child walk starts at [dlg+0x42])
#define SC_BINDLG_SIZE            0x56u   // GPTP (structures.h C_ASSERT sizeof==86);
                                          //   only zeroes a plugin-owned scratch
                                          //   BinDlg, never strides a game array.

#define SC_CTRL_FLAG_DRAWN   0x1u    // set once drawn; act sets it before updateControl
#define SC_CTRL_FLAG_VISIBLE 0x8u    // hud 2 (0x0045845D TEST [ctrl+0x18],0x8)
// CTRL_FONT_SMALLEST -- BWAPI BW/Dialog.h:17. The smallest of the font-size flags,
// so the indicator text fits the row's top edge.
#define SC_CTRL_FONT_SMALLEST 0x400u
// Control type of a left-aligned static text control (BWAPI BW/Dialog.h: cLSTATIC = 9).
// Verified at runtime before use: sc_hudrow reads the default interact/update table
// entries for type 9 and refuses to splice the indicator if either is null.
#define SC_CTRL_TYPE_LSTATIC 9

// The wireframe row's control ids: 12 buttons, packed left to right.
#define SC_HUD_FIRST_SMALL_BUTTON 0x21
#define SC_HUD_LAST_SMALL_BUTTON  0x2C
#define SC_HUD_BUTTON_COUNT       12

// A button's statUser record (allocated 8 bytes in its CREATE case at 0x0045842E):
#define SC_STATUSER_OFF_UNIT 0x0u   // CUnit*
#define SC_STATUSER_OFF_ID   0x4u   // u16 -- the grpwire.grp frame index

// Dialog event layout (read by 0x004583E0: type at +0xC, dwUser at +0):
#define SC_EVT_OFF_USER 0x00u
#define SC_EVT_OFF_TYPE 0x0Cu
#define SC_EVT_RBUTTONDOWN 7
#define SC_EVT_TYPE_USER   14
// dwUser sub-code of a completed click, where 0x004583E0 turns the button's statUser unit
// into a Select: its dwUser switch (jump table at 0x0045849C) sends case 2 to 0x0045844E
// -> CALL 0x00458220. BWAPI BW/Dialog.h names it BW_USER_ACTIVATE = 2.
#define SC_USER_ACTIVATE 2

// The event's CURSOR POSITION, and the two type codes a click trace has to tell apart.
// Both offsets come from the dialog hit test 0x00418340, which reads the event with
// `MOV AX,[ECX + 0xe]` / `MOV CX,[ECX + 0x10]` and compares them against a control's
// bounds (+0x04..+0x0A) -- so +0x0E is x and +0x10 is y, in the dialog's parent space.
// MOUSEMOVE is 3 (the status control interact 0x00457F30 opens `CMP EAX,3 / JE` on the
// type from +0x0C); it arrives thousands of times a second, so a trace drops it.
#define SC_EVT_OFF_X       0x0Eu
#define SC_EVT_OFF_Y       0x10u
#define SC_EVT_MOUSEMOVE   3
#define SC_EVT_LBUTTONDOWN 4
// The dwUser the hit test sends while asking each child "are you under the cursor":
// 0x00418340 builds a local event with dwUser 4 and type USER, then takes the FIRST
// child that returns non-zero. The queue icons' 0x00457F30 accepts it on VISIBLE alone
// (case 4 -> 0x00457F82, `TEST byte [ESI+0x18],8`), while the LSTATIC type the plugin's
// own text control uses REFUSES it (0x00419190's byte table 0x004191C4[4] = 1). That is
// why a plugin text control spliced over an icon cannot swallow a click.
#define SC_USER_HITTEST 4

// THE PRESSED BIT, and the event that clears it.
// A control of type 2 (the queue icons are type 2 -- read off the live dialog) arms
// `0x40000000` on its own bounds test when the mouse goes down (0x004E1970: cursor inside
// and not yet pressed -> `XOR [ctrl+0x18],0x40000000`), and the mouse-UP handler
// 0x004E19F0 emits the ACTIVATE only if that bit is still set (`TEST EAX,0x40000000` /
// `JE 0x4e1a5e` at 0x004E1A00, else dwUser = 2 into `CALL [ESI+0x2a]`). So the press has
// to SURVIVE from button-down to button-up or the click emits nothing. `disableControl`
// (0x00418640) is what destroys it: a NO-OP when the control is already disabled (`TEST
// AL,2 / JNE ret`), but when it actually disables it sends the control a USER event with
// dwUser = 6, and type 2's handler for that code is `AND [EDI+0x18],0xBFFFFFFF`
// (0x004E1A9E) -- clear PRESSED.
#define SC_CTRL_FLAG_PRESSED 0x40000000u
#define SC_USER_DISABLED     6

// CUnit fields the row reads. hitpoints at +0x08 is read for the DEATH signal;
// it is the field the engine's DAMAGE primitive 0x004797B0 zeroes on a kill
// (research/command-opcodes.md 6), so a damage-death reads 0 here. id at +0x64.
#define SC_CUNIT_OFF_HITPOINTS 0x08u

// The player unit list -- per-player list heads at 0x006283F8, and the CUnit
// prev/next links the engine threads them on. Derived from the unit (re)init
// 0x004A0320: it sets [unit+0x68]=0, [unit+0x6C]=head, [head+0x68]=unit, head=unit --
// a head-insert doubly linked list, indexed by the unit's owning player. The removal
// path 0x004A0740 UNLINKS a unit removed from play, so a unit NOT reachable from
// playerUnitList[player] via +0x6C has been removed (killed-and-not-yet-recycled,
// trigger RemoveUnit, archon-consumed). A TRANSPORT-loaded unit stays list-linked and a
// MIND-CONTROLLED unit relinks under its new owner, so both remain reachable -- and
// both are live, identity-correct CUnit*s that vanilla can select. The array size is
// not evidenced here; the gate reads only indices < SC_MAX_PLAYERS (8), fail-closed.
#define SC_VA_PLAYER_UNIT_LIST 0x006283F8u
#define SC_CUNIT_OFF_LIST_PREV 0x68u
#define SC_CUNIT_OFF_LIST_NEXT 0x6Cu
#define SC_MAX_UNITS_WALK      2000   // loop bound: never trust a game list to terminate

// ---------------------------------------------------------------------------
// PRODUCTION QUEUE. Full evidence, with disassembly, in
// research/production-queue.md; the committed instruction tables are
// research/data/production-queue-fields.tsv (FieldSweep over displacements 0x98 and
// 0xA4) and research/data/production-cap-sites.tsv (ImmediateSweep over the fifteen
// functions that touch the queue).
// ---------------------------------------------------------------------------

// u16[5] -- the building's production queue, a RING BUFFER whose head is the byte at
// +0xA4. Read out of `addToBuildQueue`'s own store (0x0046729B
// `MOV word ptr [EDI + ECX*0x2 + 0x98],AX`) and confirmed structurally by the clear in
// `cancelAllAndClearQueue` (0x00466E80), which writes exactly ten bytes -- five u16
// slots ending at 0xA1, hard against the energy field evidenced at 0xA2. There is no
// slack to widen into.
#define SC_CUNIT_OFF_BUILD_QUEUE      0x98u
#define SC_BUILD_QUEUE_SLOTS          5

// u8 -- which slot is the HEAD (the item currently being built). Every reader indexes
// `buildQueue[(head + i) % 5]`; `findFreeBuildQueueSlot` starts its scan here.
#define SC_CUNIT_OFF_BUILD_QUEUE_SLOT 0xA4u

// The EMPTY sentinel written into a slot that holds nothing. Nine separate instructions
// in this binary store exactly this value into the array (production-queue-fields.tsv,
// the 0x98 writes) and every reader tests against it. 228 is one past the last real
// units.dat id, which is what makes it safe as a sentinel.
#define SC_BUILD_QUEUE_EMPTY          0xE4u

// The unit-type bound the Train handler itself applies before it will queue anything
// (0x004C1C55 loads the command's u16 payload, then `CMP AX,0x6a / JNC skip`). The
// plugin uses the same bound, so it can never hold a type the engine would refuse.
#define SC_MAX_TRAINABLE_UNIT_ID      0x6Au

// u8 -- the production state machine's own state byte, driven by the tick below:
// 0/1 = "start the head item", 2 = "an item is in progress", 3/4 = idle.
#define SC_CUNIT_OFF_BUILD_STATE      0xE2u
// CUnit* -- the incomplete unit the head item is currently building (0 when none).
#define SC_CUNIT_OFF_BUILD_UNIT       0xECu
// void* -- the unit's AI record. When it exists AND its [+8] is 3 (a building AI), the
// cancel/compaction paths mirror the queue into u8[5] at ai+9 and u32[5] at ai+0x18 --
// a second, independent place the 5 is baked in. The plugin never touches it.
#define SC_CUNIT_OFF_AI               0x134u

// __stdcall(u16 unitType) with EDI = CUnit*, RET 4, returns 1 on success and 0 when the
// queue is full. THE enqueue: it calls findFreeBuildQueueSlot at 0x00467256, and a
// returned 5 -- the "no free slot" sentinel -- is the whole of the cap (`CMP EAX,0x5` /
// `JZ 0x0046728a` -> XOR EAX,EAX / RET 4). It is also where a queued item is PAID FOR,
// exactly once, at 0x004672AD..0x004672D6.
#define SC_VA_ADD_TO_BUILD_QUEUE      0x00467250u

// EDX = CUnit*, returns EAX = the free slot index, or 5 when there is none. Thirteen
// instructions, with the 5 written into three of them (loop count, wrap bound, sentinel).
// sc_prodqueue.cpp re-implements this rather than calling it; the address is what the
// re-implementation is checked against.
#define SC_VA_FIND_FREE_QUEUE_SLOT    0x004669B0u

// EAX = display index 0..4, EDI = CUnit*. Cancels one queued item: refunds it (through
// 0x00468280 for the in-progress head, 0x0042CEC0 otherwise) and compacts the ring.
#define SC_VA_CANCEL_QUEUE_SLOT       0x00466A70u
// EAX = CUnit*. Walks display indices 4..0 and cancels the LAST occupied one. This is
// what wire command 0x20 with payload 0xFE reaches.
#define SC_VA_CANCEL_LAST_QUEUED      0x00466E40u
// EAX = CUnit*. Cancels (and refunds) all five, then clears the array and the head.
// Reached from the unit-removal path 0x0049FD00 -- the evidence that vanilla REFUNDS a
// destroyed building's whole queue rather than losing it.
#define SC_VA_CANCEL_ALL_AND_CLEAR    0x00466E80u
// ECX = CUnit*, EDI = unit type. "How many of this type are queued" -- UNROLLED FIVE
// TIMES, one `(head + k) % 5` test per slot: the clearest proof the 5 is not a bound.
#define SC_VA_COUNT_TYPE_IN_QUEUE     0x00466B70u

// EAX = CUnit*. The secondary-order handler for production, dispatched every frame from
// the jump table in 0x004EC170 while the building's secondary order is train. It finishes
// the head item, clears its slot and advances the head `(head + 1) % 5`. Post-hooked, so
// the frame a slot frees is the frame an overflow item is promoted.
#define SC_VA_PRODUCTION_TICK         0x00468420u

// EAX = const u8* cmd. The receive-side handler for wire command 0x1F (Train).
#define SC_VA_CMDRECV_TRAIN           0x004C1C20u
// __stdcall(const u8* cmd), RET 4. The receive-side handler for 0x20 (Cancel Train).
// Payload u16: 0xFE = cancel the last queued item, 0xFF = nothing, else = display index.
#define SC_VA_CMDRECV_CANCEL_TRAIN    0x004C0100u
#define SC_CANCEL_TRAIN_LAST          0xFEu
#define SC_CANCEL_TRAIN_NONE          0xFFu

// Wire ids for the production opcodes, from research/data/command-opcodes.tsv.
#define SC_CMD_TRAIN                  0x1Fu
#define SC_CMD_CANCEL_TRAIN           0x20u

// The two per-unit-type cost tables, u16 indexed by units.dat id. Named from
// setPendingCost (0x0042D140), which loads both at 0x0042D149/0x0042D150 (EAX = type*2)
// and stashes them per player, and again from refundByType (0x0042CEC0), which adds the
// SAME two entries back. A plugin that spends and refunds out of these tables is
// arithmetically identical to the engine's own pair.
#define SC_VA_UNIT_MINERAL_COST       0x00663888u
#define SC_VA_UNIT_GAS_COST           0x0065FD00u

// The two per-player resource counters, u32 indexed by CUnit+0x4C -- the enqueue's own
// read-modify-write at 0x004672B4/0x004672C2 (EAX = player*4), with 0x0057F120 the gas
// counterpart. research/command-opcodes.md 3.3 names this pair "the spend".
#define SC_VA_PLAYER_MINERALS         0x0057F0F0u
#define SC_VA_PLAYER_GAS              0x0057F120u

// units.dat flag byte at [type*4]. Bit 0 set means the enqueue moves NO resources
// (0x004672A3 `TEST byte ptr [EDX*0x4 + 0x664080],0x1` / JNZ past the deduction). The
// cancel path 0x00466A70 tests the identical byte before refunding, so honouring it is
// what keeps spend and refund symmetric.
#define SC_VA_UNIT_COST_FLAGS         0x00664080u
#define SC_UNIT_COST_FLAG_NO_SPEND    0x01u

// The engine's list of ACTIVE dialogs. Head pointer; each entry is a BinDlg, threaded
// on the same +0x00 "next" link every dialog walk in this file uses.
//
// Out of THIS binary: the event dispatcher 0x00419FD0, which every posted input event
// goes through, reads the head at 0x00419FFD, steps `next` at 0x0041A008 and calls each
// entry's interact `[ECX + 0x2a]` at 0x0041A00C until the link is null -- i.e. it offers
// each event to every dialog in turn, on exactly the +0x00/+0x2A layout sc_hudrow relies
// on. The plugin only READS it (name, bounds and the same for each dialog's controls) so
// a suite can find the in-game tips dialog and its OK button rather than a fixed point.
#define SC_VA_DIALOG_LIST 0x006D5E34u
#define SC_MAX_DIALOGS_WALK 16        // loop bound, same reason as SC_MAX_UNITS_WALK
#define SC_MAX_CTRLS_WALK   64

// ---------------------------------------------------------------------------
// COMMAND CARD. Full evidence, with the decompiles and the byte-exact click/hotkey
// paths, in research/command-card.md; committed sweep tables in research/data/card-*.tsv.
// The module was found by locating its own .rdata strings in the file image and sweeping
// them for references.
//
// The card is the SIBLING of the status area above: one dialog loaded from
// rez\statbtn%c.bin, whose controls are ids 1..9 -- the nine card slots, in reading
// order. Every slot's behaviour comes from a 20-byte Button record in the per-unit
// BUTTONSET the current selection resolves to.
// ---------------------------------------------------------------------------

// BinDlg* -- the command-card dialog. Written by the card init 0x00459B90 (which
// loads "rez\statbtn%c.bin"), cleared by the teardown 0x00458CF0, read by the
// layout 0x004591D0, the hotkey handler 0x00458B30 and the mouse router 0x004597C0.
#define SC_VA_CARD_DIALOG 0x0068C148u

// u16 -- the CURRENT CARD ID: the buttonset the card is drawn from. The per-frame
// card update 0x004599A0 sets it from the portrait unit's own buttonset id
// (CUnit+0x94) unless one of the two overrides below is not 0xE4.
#define SC_VA_CARD_ID 0x0068C14Cu

// u16 -- the two card-id OVERRIDES, 0xE4 (228) = "none". 0x0068C1C4 is the SELECTION
// override computed by 0x00458BC0: it walks clientSelectionGroup and, when the selected
// units do not share a buttonset, writes 0xF4 (the basic card) or one of 0xF5/0xF6/0xF7
// (the all-of-a-kind group cards) -- research/command-opcodes.md 8's "a MIXED selection
// is offered only the basic command card", off the binary rather than observed.
// 0x0068C1C8 is the SUBMENU override (build menus etc.).
#define SC_VA_CARD_OVERRIDE_SEL 0x0068C1C4u
#define SC_VA_CARD_OVERRIDE_SUB 0x0068C1C8u
#define SC_CARD_ID_NONE 0x00E4u

// BinDlg* -- the card control currently under the cursor (0x00459770/0x004597C0).
#define SC_VA_CARD_HOVER 0x0068C1B4u

// u32 -- the REASON CODE every ability condition writes before returning 0 or -1. Set by
// the tech gate 0x0046DD80 and the requirement interpreter 0x0046D610; read by the layout
// 0x004591D0, which rewrites the button's disabled-reason string to 0x2FA when it is 0x15.
#define SC_VA_CARD_REFUSE_REASON 0x0066FF60u

// The BUTTONSET table: 250 entries x 12 bytes. Its length is read off the binary, not
// assumed -- entry 250 would start at 0x005193A0, exactly where the per-unit-type status
// cond/act table named in hud-selection-row.md 4.2 begins.
#define SC_VA_BUTTONSET_TABLE 0x005187E8u
#define SC_BUTTONSET_STRIDE   0x0Cu
#define SC_BUTTONSET_COUNT    250
#define SC_BUTTONSET_OFF_N    0x00u   // u16 -- how many buttons
#define SC_BUTTONSET_OFF_PTR  0x04u   // Button* -- the array

// A Button: 20 bytes. Every offset is proven by an instruction here (command-card.md 3):
//   +0x00 slot     layout 0x004591D0 compares it against the control's index
//   +0x02 icon     layout writes it into the control's graphic (+0x24)
//   +0x04 cond     layout CALLs it; 0 = not on the card, >0 = enabled, <0 = greyed
//   +0x08 action   the click path 0x0045990F does `CALL dword ptr [ESI+0x8]`
//   +0x0C condParam  passed to the condition
//   +0x0E actParam   the click path does `MOV CX,word ptr [ESI+0xE]` first
//   +0x10 nameStr    the hotkey predicate 0x004588C0 does `MOV CX,[EAX+0x10]`
//   +0x12 disStr     layout overwrites it with 0x2FA when the refuse reason is 0x15
#define SC_BUTTON_SIZE           20u
#define SC_BUTTON_OFF_SLOT       0x00u
#define SC_BUTTON_OFF_ICON       0x02u
#define SC_BUTTON_OFF_COND       0x04u
#define SC_BUTTON_OFF_ACTION     0x08u
#define SC_BUTTON_OFF_COND_PARAM 0x0Cu
#define SC_BUTTON_OFF_ACT_PARAM  0x0Eu
#define SC_BUTTON_OFF_NAME_STR   0x10u
#define SC_BUTTON_OFF_DIS_STR    0x12u

// The card's nine control ids, 1..9 in reading order. The layout function walks to
// the child with index == 1 and stops treating children as slots once the index is
// >= 10 (`if ((short)ctrl->index < 10)`), so the range is the binary's, not a guess.
#define SC_CARD_FIRST_CONTROL 1
#define SC_CARD_LAST_CONTROL  9
#define SC_CARD_SLOTS         9

// THE flag that greys a card button. 0x00418640 sets bit 1 of control+0x18 and
// 0x00418E00 clears it; the layout function picks between them on the sign of the
// condition. BOTH input paths then refuse a control that carries it:
//   mouse: 0x00459947 (the card button interact's LBUTTONDOWN case) does
//          `TEST byte ptr [ESI+0x18],0x2` and returns 0 -- the click is swallowed;
//   key:   0x004588C0 (the hotkey predicate the handler 0x00458B30 passes to the
//          child walk 0x00417EB0) does the same test and never matches the button.
// So a greyed card button emits nothing, arms nothing, and logs nothing.
#define SC_CTRL_FLAG_DISABLED 0x2u

// CUnit+0x94 -- the unit's own buttonset id. Read by the per-frame card update 0x004599A0
// (`MOV ..,[portrait+0x94]`) and by the mixed-selection resolver 0x00458BC0, which uses it
// BOTH as the buttonset-table index and as the value it compares across the selection.
#define SC_CUNIT_OFF_BUTTONSET 0x94u

// The per-tech energy cost table the cloak SEND gate 0x00423540 reads:
// cost = *(u8*)(0x00656380 + techId*2), compared as (cost << 8) <= CUnit+0xA2.
#define SC_VA_TECH_ENERGY_COST 0x00656380u
// Personnel Cloaking. The id ability-semantics.md 3 derives from the receive-side
// handler 0x00491B30, and the value the Ghost's Cloak button carries as its
// conditionParam -- two independent derivations agreeing.
#define SC_TECH_PERSONNEL_CLOAKING 10
#define SC_TECH_CLOAKING_FIELD      9

// ---------------------------------------------------------------------------
// The PRODUCTION QUEUE STRIP in the status pane. The five icons a player clicks to
// cancel a queued unit are ordinary controls of the statdata dialog
// (SC_VA_STATDATA_DIALOG), ids 2..6. Read out of two functions here:
//
//   queueLayout 0x004268D0 -- the layout the per-unit-type status act 0x00427890
//     dispatches to for a producing building. It walks to the child with `index == 2`,
//     steps `next` FIVE times, k = 0..4, and lays out
//     `buildQueue[(buildQueueSlot + k) % 5]` (CUnit+0x98/+0xA4), so DISPLAY INDEX k is
//     head-relative and the icon a slot draws is the queued unit type itself. What it
//     writes per slot is spelled out below, at SC_VA_GRP_CMDICONS.
//   statusCtrlActivate 0x004573A0 -- the activation the control interact 0x00457F30
//     calls at 0x00457F75 on the USER event. Cases 2..6 of control->index fall into one
//     block that queueCommands {0x20, index - 2} (0x004573D6..0x004573E9), so clicking
//     icon k reaches cancelBuildQueueSlot(EAX = k), which refunds and compacts.
//
// The disabled bit is SC_CTRL_FLAG_DISABLED, and on this STRIP it refuses nothing: the
// icon's own hit-test answer 0x00457F82 tests `flags & 8` (VISIBLE) and nothing else, and
// neither the type-2 LBUTTONDOWN nor LBUTTONUP path reads 0x2. What the bit DOES decide is
// the DRAWN COLOURS: the icon blit 0x00456C30 tests exactly it (0x00456C3D) and picks
// ticon.pcx remap row 4 (disabled) over row 3 (enabled) -- 14 of 16 entries differ. So the
// bit greys the PIXELS while refusing nothing: clearing it does not make a slot clickable,
// and leaving it set to dodge the disable event draws the slot grey.
// research/production-queue.md 8.1.
#define SC_STATQ_FIRST_CONTROL 2
#define SC_STATQ_LAST_CONTROL  6
#define SC_STATQ_SLOTS         5

// queueLayout itself (quoted above), which the plugin detours: __stdcall(BinDlg* ctrl),
// RET 4, and it re-reads the portrait unit global 0x00597248 for every slot rather
// than caching it. Its prologue (PUSH EBP / MOV EBP,ESP / SUB ESP,0x20) is 6 bytes of 3
// whole instructions, none PC-relative, so they relocate into the trampoline unchanged
// and the 5-byte JMP + 1 spare byte fits exactly.
#define SC_VA_QUEUE_LAYOUT 0x004268D0u

// The queue icon's statUser record: 12 bytes, allocated by the status control's
// CREATE case (0x00457CA0: `SMemAlloc(0xC, "statdata.cpp", 0x273)` -> control+0x26)
// and written by queueLayout as quoted above.
#define SC_STATUSER_OFF_GRP  0x00u   // the GRP the icon is drawn from
#define SC_STATUSER_OFF_ICON 0x04u   // s16 -- the frame drawn: the unit type, or k+6 when empty
#define SC_STATUSER_OFF_MODE 0x06u   // u16 -- 3 for an occupied slot, 6 for an empty one
#define SC_STATUSER_OFF_TYPE 0x08u   // s16 -- the unit type again, occupied slots only

// ---------------------------------------------------------------------------
// What queueLayout writes per slot -- FIVE fields, and the two easiest to miss are what
// decide which ART the slot draws. Disassembled from this binary:
//   OCCUPIED (0x00426A33..0x00426A55)  statUser->grp = [0x0068C1E0] (the ICON grp),
//     icon = unit type, mode = 3, type = unit type, ENABLE 0x00418E00, and
//     ctrl->pszText = the slot label out of 0x00519F40.
//   EMPTY, 0xE4 (0x00426A5A..0x00426A74)  statUser->grp = [0x0068C1C0] (the
//     BUTTON-BORDER grp), icon = k + 6, mode = 6, DISABLE 0x00418640,
//     ctrl->pszText = NULL.
//
// The two GRP handles are DIFFERENT ART, and the draw takes the frame index and the GRP
// from the SAME record -- the icon blit 0x00456C30 loads `frame = statUser->icon` and
// `grp = statUser->grp` at 0x00456C80/0x00456C84 and clamps an out-of-range frame to 0.
// So a record carrying an occupied slot's frame index and an EMPTY slot's GRP draws frame
// #unitType out of the button-border art: different garbage per queued unit type,
// constant while that type is queued. Filling a slot the engine laid out for another
// purpose therefore means writing EVERY field that layout wrote, not just the ones that
// look like the payload.
//
// Resolved to files at their load sites:
//   0x0068C1E0 <- 0x00459C2A, name at 0x00504A24 = "unit\cmdbtns\cmdicons.grp"
//   0x0068C1C0 <- 0x00459C0C, "%s%ccmdbtns.grp" + "unit\cmdbtns\" + the race letter
//                 from 0x00512700 "ztp" -- the command BUTTON BORDER art.
#define SC_VA_GRP_CMDICONS 0x0068C1E0u   // unit\cmdbtns\cmdicons.grp -- occupied slots
#define SC_VA_GRP_CMDBTNS  0x0068C1C0u   // <race>cmdbtns.grp -- empty-slot placeholders

// The five slot LABELS, `char*[5]` -- the little numbers on the strip's icons. queueLayout
// formats "%d " (k+1) into buffer k before it branches (0x004269EE-0x00426A02, the k==0
// variant taking the colour-coded form), then points an occupied slot's pszText at it.
#define SC_VA_STATQ_SLOT_LABELS 0x00519F40u

// ---------------------------------------------------------------------------
// PER-PLAYER TECH STATE -- the memory an ability button is gated on, and therefore the
// memory that decides whether a fixture really granted a tech. Two pairs of arrays,
// [player][tech] (research/command-card.md 6):
//   AVAILABLE  -- read by 0x004CE8A0. The tech gate 0x0046DD80 turns a false here into
//                 reason 2 and return 0, which HIDES the button.
//   RESEARCHED -- read by 0x004CE850 and by requirement opcode 0xFF0F inside the
//                 interpreter 0x0046D610. A false here leaves the requirement count at
//                 zero, the interpreter's `reason = 8; return -1` exit -- and -1 is what
//                 the card layout turns into a GREYED button.
// So "visible but greyed" is a precise statement: available yes, researched no.
//
// Confirmed by sweep (research/data/card-tech-state.tsv): the only writer of all four
// is the CHK applier pair 0x004CB670 (PTEC, 24 techs) / 0x004CB7D0 (PTEx, 44), and
// 0x004CCC80 is the REP STOSD that clears them at game start. Each pair is adjacent by
// exactly its own size (0x120 = 12*24, 0xF0 = 12*20), so the strides are read off the
// layout rather than asserted.
#define SC_VA_TECH_AVAILABLE     0x0058CE24u   // u8[12][24]
#define SC_VA_TECH_RESEARCHED    0x0058CF44u   // u8[12][24]
#define SC_VA_TECH_AVAILABLE_BW  0x0058F038u   // u8[12][20], techs 24..43
#define SC_VA_TECH_RESEARCHED_BW 0x0058F128u   // u8[12][20]
#define SC_TECH_COUNT_VANILLA    24
#define SC_TECH_COUNT_BW         20            // 44 total
#define SC_TECH_STRIDE_VANILLA   0x18u
#define SC_TECH_STRIDE_BW        0x14u

// ---------------------------------------------------------------------------
// The client-side gate in front of GROUP PRODUCTION.
//
// Measured first, then read. With four Command Centers selected, the card walked out of
// the engine's own memory shows the Train button not greyed but ABSENT
// (`button=0x00000000`, no Button record on its control); with ONE selected it is enabled.
// The three slots that vanish are exactly the three whose condition is 0x00428E60 (Train
// and the two addon buttons); the two that survive are the two that are not (0x00429520
// rally, 0x004287D0). So the refusal is in that one function.
//
// Its whole body, from this binary: it takes the type from ECX, compares the client's
// selection COUNT byte [0x0059723D] against 1 and ALLOWs when count <= 1 (0x00428E71
// JBE); otherwise it accepts only CUnit+0x64 in {0x23, 0x2B, 0x26} -- the Zerg types
// that multi-select anyway -- and returns 0. The allow path pushes EDX and tail-calls
// the requirement gate 0x0046E1C0.
//
// So the convention is `__stdcall(CUnit* unit)` with ECX = the button's type param and
// EDX = the player, and the count is a BYTE. EDX is corroborated independently by the
// neighbouring condition 0x00429520, which compares its own EDX against the unit's
// owner byte at CUnit+0x4C.
#define SC_VA_BTN_TRAIN_CONDITION  0x00428E60u
// The multi-select count the condition tests. A BYTE (`CMP byte ptr [..],1`). The plugin
// LOGS it beside the selection size, so "this is the client's selection count" is a
// reading the in-game suite asserts (it must read 4 with four buildings boxed), not a
// label.
#define SC_VA_CLIENT_SELECTION_COUNT 0x0059723Du
// The condition's tail call: the player's requirement/tech interpreter. Convention, read
// off its own body: **ESI = the PRODUCING unit**, **AX = the type being built**, and the
// player as its one stack argument (the `PUSH EDX` above), `RET 4`.
//
// It is emphatically NOT a player-only check, which is what decides what happens to a
// group whose buildings cannot all build the unit: opcode 0xFF02 compares the required
// type against the producer's own `CUnit+0x64` and returns -1 (reason 0x19) on a
// mismatch, and 0xFF04 / 0xFF0C check the producer's own ADDON pointer at `CUnit+0xC0`.
// The Train handler tests `== 1` exactly, so a -1 refuses before addToBuildQueue runs and
// therefore before any resource moves.
#define SC_VA_REQUIREMENT_GATE     0x0046E1C0u
// The Train handler's own bound on the type it will accept (`< 0x6A`,
// research/production-queue.md 4.1). Reused here as the discriminator between the Train
// buttons and the two ADDON buttons that share this condition: a Train button's param is
// a unit type below this, an addon button's is a building type (107, 108) above it.
#define SC_TRAIN_TYPE_LIMIT        0x6Au

// ---------------------------------------------------------------------------
// UPGRADES AND RESEARCH. Evidence: research/upgrade-queue.md, whose every address
// carries how it was found; the committed instruction table is
// research/data/upgrade-fields.tsv.
//
// A building researches ONE thing at a time because it has ONE FIELD for it. The two
// fields below come from the two button conditions that read them, which cross-check
// each other -- one requires "idle", the other "busy":
//   0x00428900  return unit->0xC9 != '='   (61)  -> show Cancel Upgrade
//   0x004287D0  requires 0xC8 == ',' (44) AND 0xC9 == '=' (61) -> allow Lift Off
// 61 and 44 are one past the last upgrades.dat / techdata.dat id, the same
// one-past-the-end sentinel the build queue uses at 0xE4.
//
// THESE BYTES ARE A UNION ARM. 0x00469240 stores a CUnit* at +0xC8 for a unit that is
// not a researching building, so every read must be gated on the BUILDING flag -- which
// is what all three engine readers do.
#define SC_CUNIT_OFF_RESEARCH_TIME     0xC6u  // u16, counts down once per frame
#define SC_CUNIT_OFF_TECH_PROGRESS     0xC8u  // u8 techdata.dat id being researched
#define SC_CUNIT_OFF_UPGRADE_PROGRESS  0xC9u  // u8 upgrades.dat id being researched
#define SC_CUNIT_OFF_UPGRADE_LEVEL     0xCDu  // u8, the level being upgraded TO
#define SC_TECH_NONE     44u   // 0x2C
#define SC_UPGRADE_NONE  61u   // 0x3D
#define SC_TECH_COUNT    44
#define SC_UPGRADE_COUNT 61

// CUnit+0xDC bits, from the guards the engine puts in front of the two fields above:
// upgradeTick 0x004546A0 opens `flags & 2`, and the upgrade gate 0x0046DFC0 refuses with
// reason 0x14 when `flags & 1` is clear -- the second of which is SC_UNIT_FLAG_COMPLETED,
// derived independently above from a production run and defined there.
#define SC_UNIT_FLAG_BUILDING   0x2u

// The LOCAL player id, as the two receive handlers read it -- `MOV EDI,[0x00512678]` at
// 0x004C1B49 and 0x004C1BC9, and `CMP [ESI+0x4C], [0x00512678]` inside
// cmdrecvCancelUpgrade. NOT SC_VA_ACTIVE_PLAYER_ID (0x0051267C), which selNext 0x0049A850
// multiplies by 12 to index the selection array; the two are adjacent, never the same.
#define SC_VA_LOCAL_PLAYER_ID  0x00512678u

// The detour targets. Every one is an ENTRY-POINT verdict from HookProbe over
// tools/ghidra/specs/upgrade-hooks.spec, with a relocation-safe patch window.
//   btnUpgradeCondition / btnTechCondition  The CARD's own conditions, 20-byte wrappers
//       that marshal CL/EDX into the gate. Hooked INSTEAD of the gates themselves: the
//       gates have a third caller each in the building-AI range (0x00434670, 0x004345C0),
//       and a computer player told a busy building is free would issue an upgrade that
//       startUpgrade then applies on top of the running one. The conditions have no CALL
//       references at all -- the button table reaches them as DATA -- so hooking them
//       touches the card and nothing else.
//   cmdrecvUpgrade / cmdrecvTech  __stdcall(const u8* cmd), RET 4; the id is cmd[1]; the
//       acting building is the sole selected unit; the player is [0x00512678].
//   upgradeTick / techTick  The order handlers. EAX = CUnit*, void, bare RET. They count
//       0xC6 down and, on completion, clear 0xC9/0xC8 and raise the level / set the
//       researched byte.
//   cmdrecvCancelUpgrade / cmdrecvCancelTech  0x33 / 0x31. NO arguments at all -- they
//       resolve the building through the same selection test -- and both end in a bare
//       RET, so a plain void(void) detour fits.
#define SC_VA_BTN_UPGRADE_COND       0x00429450u
#define SC_VA_BTN_TECH_COND          0x00429500u
#define SC_VA_CMDRECV_UPGRADE        0x004C1B20u
#define SC_VA_CMDRECV_TECH           0x004C1BA0u
#define SC_VA_CMDRECV_CANCEL_UPGRADE 0x004BFFC0u
#define SC_VA_CMDRECV_CANCEL_TECH    0x004C0070u
#define SC_VA_UPGRADE_TICK           0x004546A0u
#define SC_VA_TECH_TICK              0x004548B0u

// The engine's own accept path, called at promotion time so that the ENGINE pays.
// Conventions read straight off cmdrecvUpgrade's listing (0x004C1B3F..0x004C1B71):
//   upgradeGate  __stdcall(unit) with BX = id, EDI = player  -> EAX, 1 = accept
//   startUpgrade AL = id, ECX = unit -> EAX non-zero on success (and it PAYS)
//   startTech    AL = id, EDX = unit -> EAX non-zero on success (and it PAYS)
//   afterAccept  CL = order id, ESI = unit, void
#define SC_VA_UPGRADE_GATE   0x0046DFC0u
#define SC_VA_TECH_GATE      0x0046DE90u
#define SC_VA_START_UPGRADE  0x00454A80u
#define SC_VA_START_TECH     0x00454B70u
#define SC_VA_AFTER_ACCEPT   0x00475310u
#define SC_ORDER_UPGRADE  0x4Cu   // `MOV CL,0x4C` at 0x004C1B6F -- and the order the live
                                  // probe measured on a researching Engineering Bay
#define SC_ORDER_RESEARCH 0x4Bu   // `MOV CL,0x4B` at 0x004C1BEF

// The four redraw globals both handlers write after a successful accept
// (0x004C1B78..0x004C1B8F). SC_VA_STAT_DIRTY (0x0068C1F8) is already defined above.
#define SC_VA_REDRAW_CARD    0x0068C1B0u  // u32
#define SC_VA_REDRAW_CONSOLE 0x0068AC74u  // u8
#define SC_VA_REDRAW_SEL_A   0x0068C1E8u  // u32, cleared
#define SC_VA_REDRAW_SEL_B   0x0068C1ECu  // u32, cleared

// Per-player upgrade levels, named off the two accessors whose whole bodies are the index
// computation -- 0x004CE7A0 (current) and 0x004CE7F0 (max) -- and confirmed by the same
// expression appearing verbatim in startUpgrade, upgradeRefund, 0x0042D190 and 0x00453F70.
#define SC_VA_UPGRADE_LEVEL      0x0058D2B0u  // u8[12][46]
#define SC_VA_UPGRADE_MAX_LEVEL  0x0058D088u  // u8[12][46]
#define SC_VA_UPGRADE_LEVEL_BW   0x0058F2FEu  // u8[?][15], upgrades 46..60 (base biased)
#define SC_VA_UPGRADE_MAX_BW     0x0058F24Au
#define SC_UPGRADE_STRIDE_VANILLA 0x2Eu  // 46
#define SC_UPGRADE_STRIDE_BW      0x0Fu  // 15
#define SC_UPGRADE_COUNT_VANILLA  46

// "This PLAYER is already researching this UPGRADE / TECH, somewhere." Bitfields, set by
// the two starts, cleared by the two ticks and the two cancels, tested by 0x004281B0 and
// 0x00428240 which the gates call. The rule that keeps two buildings off the same upgrade;
// untouched here, which is why queueing level N+1 behind N is refused (upgrade-queue.md 8.2).
#define SC_VA_UPGRADE_INPROGRESS_BITS 0x0058F3E0u  // 8 bytes per player
#define SC_VA_TECH_INPROGRESS_BITS    0x0058F230u  // 6 bytes per player
#define SC_UPGRADE_BITS_STRIDE 8u
#define SC_TECH_BITS_STRIDE    6u

// Costs. An upgrade's is base + factor*currentLevel out of four u16 tables (0x0042D190,
// 0x00454170 and 0x00453F70 all read the same pairs); a tech's is two flat u16 lookups
// (startTech 0x00454B70, inline). Read ONLY to decide whether the player can afford an
// item before handing it to the engine -- the plugin never spends.
#define SC_VA_UPGRADE_MINERAL_BASE   0x00655740u
#define SC_VA_UPGRADE_MINERAL_FACTOR 0x006559C0u
#define SC_VA_UPGRADE_GAS_BASE       0x00655840u
#define SC_VA_UPGRADE_GAS_FACTOR     0x006557C0u
#define SC_VA_TECH_MINERAL_COST      0x00656248u
#define SC_VA_TECH_GAS_COST          0x006561F0u

// The ICON a research draws, read off the two research layouts of the status pane, which
// fill their own icon control (id SC_STAT_RESEARCH_ICON_CONTROL) with the same five
// fields queueLayout writes for a queued unit:
//   0x00426500 (upgrade)  statUser->grp = [SC_VA_GRP_CMDICONS], icon = u16[0x00655AC0 +
//                         unit->0xC9 * 2], mode = 5, type = unit->0xC9, then 0x00418E00
//   0x004266F0 (tech)     the same with u16[0x00656430 + unit->0xC8 * 2] and mode = 4
// so both tables index cmdicons.grp, exactly as the card's button records do.
#define SC_VA_UPGRADE_ICON 0x00655AC0u   // u16[61]
#define SC_VA_TECH_ICON    0x00656430u   // u16[44]
#define SC_STATUSER_MODE_UNIT    3        // queueLayout's occupied slot
#define SC_STATUSER_MODE_TECH    4
#define SC_STATUSER_MODE_UPGRADE 5
#define SC_STAT_RESEARCH_ICON_CONTROL 15  // the research layouts' own icon, at slot 0's place
// RENDERER / VIEWPORT. Full evidence, with the decompiles, in
// research/renderer-viewport.md. Nothing here is inherited: the renderer is the one
// subsystem BWAPI, GPTP and OpenBW all skip (research/prior-art.md 9). The modules were
// found by locating the binary's own __FILE__ strings (gds\vidinimo.cpp and friends) in
// the file image and sweeping them for references.
//
// EVERY VALUE BELOW IS THE STOCK GEOMETRY, not what a running process necessarily holds:
// the readers (scplugin.cpp's SCREEN scan behind %SCPLUGIN_SCREENSCAN%, sc_circles,
// sc_console) see it unchanged, but the widescreen path writes here -- sc_screen.cpp
// rewrites the 640/480 immediates inside these very functions and sc_stormpresent re-sets
// the cursor layer's always-draw bit.
// ---------------------------------------------------------------------------

// THE screen buffer descriptor: { u16 width; u16 height; u8* data }. The whole game --
// terrain, sprites, fog, HUD, dialogs, cursor -- is composed into this one 8-bit linear
// buffer, and the frame is one blit out of it. Written twice with the same three values:
// the graphics-layer init 0x0041E050 (gds\image.cpp) sets {640,480,NULL}, and the video
// init 0x004DB060 (gds\vidinimo.cpp) sets them again at 0x004DB07C/0x004DB085 and fills
// the pointer with SMemAlloc(0x4B000) -- exactly 640*480 bytes.
#define SC_VA_SCREEN_BITMAP        0x006CEFF0u
#define SC_BITMAP_OFF_WIDTH        0x00u   // u16
#define SC_BITMAP_OFF_HEIGHT       0x02u   // u16
#define SC_BITMAP_OFF_DATA         0x04u   // u8*
#define SC_SCREEN_W                640
#define SC_SCREEN_H                480

// GraphicLayer[8], 20 bytes each. The frame composer 0x0041E280 walks them from index 7 down
// to 0 -- so layer 7 is the BOTTOM and layer 0 is drawn LAST, on top -- and calls each one's
// draw callback with (layer->param, &clipRect). The stride is the binary's: 0x004BD630
// indexes the block as `(&DAT_006CEF51)[i * 0x14]`, and the gds\image.cpp init 0x0041E050
// zeroes exactly 0x28 dwords = 8 * 20 bytes starting here, ending precisely where
// SC_VA_SCREEN_BITMAP begins.
#define SC_VA_GRAPHIC_LAYERS       0x006CEF50u
#define SC_GRAPHIC_LAYERS          8
#define SC_LAYER_STRIDE            0x14u
#define SC_LAYER_OFF_USED          0x00u   // u8
#define SC_LAYER_OFF_FLAGS         0x01u   // u8; bit 0 = needs redraw
// The composer 0x0041E280 draws a layer when `test bl,0x21` (0x0041E35F) is non-zero,
// else when its rect covers a dirty cell, else when bit 0x02 is set; after a draw it
// masks the flags with 0xF8 (0x0041E3A3), which CLEARS 0x01/0x02/0x04 and KEEPS 0x20.
// Every writer of layer 0's flags byte in the image is a read-modify-write OR of 0x01,
// never a plain store -- so 0x20, once set, is sticky and means "compose this layer every
// frame"; the dialog layer's setup 0x0041A030 ships layer 2 with `mov byte
// [0x6CEF79],0x20`, the only plain store of the bit in the image. The only wipe is the
// layer-table init 0x0041E050, which is why the storm present widen re-sets it on the
// cursor layer every present (sc_stormpresent.cpp, renderer-viewport.md 21.9).
#define SC_LAYER_FLAG_NEEDS_REDRAW 0x01u
#define SC_LAYER_FLAG_ALWAYS_DRAW  0x20u
#define SC_LAYER_OFF_LEFT          0x02u   // s16
#define SC_LAYER_OFF_TOP           0x04u   // s16
#define SC_LAYER_OFF_WIDTH         0x06u   // s16
#define SC_LAYER_OFF_HEIGHT        0x08u   // s16
#define SC_LAYER_OFF_PARAM         0x0Cu   // void*  -- first argument to the draw callback
#define SC_LAYER_OFF_DRAW          0x10u   // void (*)(void* param, s16 clip[5])

// Which layer is which, read off the writer of each layer's +0x10 draw slot:
//   0  0x004BDFA0, installed by 0x004D1560 (cur.cpp)          -- cursor, drawn last
//   1  0x004810F0, installed by 0x00481330 (CtxtHelp.cpp)     -- the context-help TOOLTIP
//      (the installer's allocator calls carry the __FILE__ string 0x005044F0
//      "Starcraft\SWAR\lang\CtxtHelp.cpp"; the draw blits the 160x92 tooltip surface
//      0x00655C40 at the layer's rect; show 0x004813D0, hide 0x00481480)
//   2  0x0041CB50, installed by 0x0041A030, 640x480  -- DIALOGS (walks SC_VA_DIALOG_LIST)
//   3  0x0048D5C0, installed by 0x0048D700                    -- build-placement preview
//   4  0x0048D5C0, same installer                             -- second placement slot
//   5  0x004BD580, installed by 0x004BD630, 640x400           -- THE PLAYFIELD
//   6, 7  no writer of either draw slot anywhere in the binary -- unused
#define SC_LAYER_CURSOR       0
#define SC_LAYER_TOOLTIP      1
#define SC_LAYER_DIALOGS      2
#define SC_LAYER_PLACEMENT_A  3
#define SC_LAYER_PLACEMENT_B  4
#define SC_LAYER_PLAYFIELD    5

// The tooltip's own state beside its layer record: the draw 0x004810F0 blits only while
// this u32 is non-zero (set 1 by the show 0x004813D0, 0 by the hide 0x00481480).
#define SC_VA_TOOLTIP_VISIBLE      0x00655C48u
// Layer 1's rect {s16 left, top, width, height} = SC_VA_GRAPHIC_LAYERS + stride + LEFT;
// named because the frame driver 0x0041CA00 and the hit test 0x0041BE70 read it as a
// rect, and a probe following the tooltip needs the same four words.
#define SC_VA_TOOLTIP_LAYER_RECT   0x006CEF66u

// THE PLAYFIELD SIZE, and it is not stored anywhere -- it is an immediate in every function
// that clips to it. 640x400 out of the 640x480 screen; the console art and the HUD dialogs
// are drawn OVER the bottom of it rather than beside it. Independent copies of the same two
// numbers, read for research/renderer-viewport.md: layer 5's own width/height 0x004BD630,
// the per-IMAGE screen clip 0x004D57B0 that every sprite goes through, the generic rect
// clip 0x0045CC90, the click handler's search rect 0x0046FB40, build placement 0x0048D660,
// the fog and terrain dirty-grid walks 0x004808E0 / 0x004BCDC0, and fog-of-war clipping
// 0x0047EBF0, 0x0047EE20, 0x004808F8.
#define SC_PLAYFIELD_W             640
#define SC_PLAYFIELD_H             400

// The DIRTY-BLOCK GRID: u8[30][40], one byte per 16x16 pixel block of the 640x480 screen.
// Established by the marker 0x0041E0D0, which clamps x to 0x27F and y to 0x1DF, shifts both
// right by 4 and writes at `&DAT_006CEFF8 + row * 0x28 + col`. Three separate functions clear
// it as "300 dwords" = 1200 bytes = 40 * 30, and 0x0041D470 tells the presentation layer the
// same geometry explicitly with `Ordinal_440(0x280, 0x1e0, 0x10, 0x10)`.
//
// IT CANNOT GROW IN PLACE. 0x006CEFF8 + 0x4B0 == 0x006CF4A8, a live global (the current
// render-target Bitmap*, written by 0x0041E280 and 0x0041DF40 among others).
#define SC_VA_DIRTY_GRID           0x006CEFF8u
#define SC_DIRTY_BLOCK             16
#define SC_DIRTY_COLS              40      // 0x28, the row stride in 0x0041E0D0
#define SC_DIRTY_ROWS              30
#define SC_VA_RENDER_TARGET        0x006CF4A8u  // the global immediately after the grid

// The terrain scratch surface the tile blitter 0x004BCDC0 reads through: pitch 0x2A0 = 672,
// total 0x49800 = 301056 = 672 * 448, addressed modulo its own size so a scroll wraps rather
// than copies. 672 = 640 + 32 and 448 = 400 + 48 -- the playfield plus a tile of margin.
#define SC_TERRAIN_SCRATCH_PITCH   0x2A0u
#define SC_TERRAIN_SCRATCH_SIZE    0x49800u

// The scroll clamp. 0x0049BB90 establishes both maxima from the map's tile dimensions and
// the VIEWPORT'S SIZE IN TILES -- `(mapTileW - 0x14) * 0x20` and `(mapTileH - 0x0C) * 0x20
// + 8` -- and the two scroll steppers 0x0049C0C0 (x) / 0x0049C280 (y) clamp against these.
#define SC_VA_SCROLL_MAX_X         0x00628488u  // u32
#define SC_VA_SCROLL_MAX_Y         0x006284B0u  // u32
#define SC_VA_MAP_PIXEL_W          0x006284A4u  // u16, mapTileW << 5
#define SC_VA_MAP_PIXEL_H          0x006284A6u  // u16, mapTileH << 5
#define SC_VIEWPORT_TILES_X        20     // 0x14 in 0x0049BB90 and 0x004A4D20
#define SC_VIEWPORT_TILES_Y        12     // 0x0C in 0x0049BB90 (0x0D in 0x004A4D20)

// The TILE-granular viewport origin, written by every scroll stepper as origin >> 5, and the
// map's tile dimensions beside it. The minimap reads the first pair (0x004A4D20, 0x004A5A80)
// and the second (0x004A3A40, 0x004A41B0).
#define SC_VA_SCREEN_TILE_X        0x0057F1D0u  // u16
#define SC_VA_SCREEN_TILE_Y        0x0057F1D2u  // u16
#define SC_VA_MAP_TILE_W           0x0057F1D4u  // u16
#define SC_VA_MAP_TILE_H           0x0057F1D6u  // u16

// The engine's own renderer functions -- NOT hooked or patched; recorded because every
// claim above names one of them.
#define SC_VA_VIDEO_INIT           0x004DB060u  // gds\vidinimo.cpp: sets the screen Bitmap
#define SC_VA_DDRAW_INIT           0x0041D930u  // gds\vidinimo_PC.cpp: SetDisplayMode(640,480,8)
#define SC_VA_GFX_LAYER_INIT       0x0041E050u  // gds\image.cpp: zeroes the layer block
#define SC_VA_FRAME_COMPOSE        0x0041E280u  // walks layers 7..0, builds each clip rect
#define SC_VA_MARK_DIRTY           0x0041E0D0u  // the dirty-grid marker
#define SC_VA_PRESENT_BLIT         0x0041D420u  // lock, Ordinal_432(dst, screen, pitch, 0x280), unlock
#define SC_VA_SURFACE_REBUILD      0x0041D470u  // Ordinal_440(0x280, 0x1e0, 0x10, 0x10)
#define SC_VA_PLAYFIELD_DRAW       0x004BD580u  // layer 5's callback: the whole playfield chain
#define SC_VA_TERRAIN_DRAW         0x004BCDC0u  // the tile blitter
#define SC_VA_IMAGE_SCREEN_CLIP    0x004D57B0u  // per-image clip to 640x400
#define SC_VA_RECT_CLIP_PLAYFIELD  0x0045CC90u  // generic rect clip to 640x400
#define SC_VA_SCROLL_SET_BOUNDS    0x0049BB90u  // establishes both scroll maxima
#define SC_VA_SCROLL_STEP_X        0x0049C0C0u
#define SC_VA_SCROLL_STEP_Y        0x0049C280u
#define SC_VA_MINIMAP_CLICK        0x004A4D20u  // centres the camera; bakes 20 x 13 tiles

// ---------------------------------------------------------------------------

// THE OTHER SELECTION INPUT PATHS. Full evidence, with the decompiles and listings
// these came from, in research/building-groups.md 8.
//
// `unit_IsStandardAndMovable` (0x0047B770) is consulted on three more client paths
// besides the DRAG BOX -- shift-click ADD, combineSelectionsLists and control-group
// recall -- and each refuses a building in its own way, so relaxing the drag-box gate
// alone does not make buildings behave like units.
// ---------------------------------------------------------------------------

// The click handler. __fastcall-ish (EDX/ECX carry the click), no stack arguments; it
// resolves the unit under the cursor with 0x0046F3A0 and returns at once if there is
// none. Its branches, told apart by two bytes of the engine's own keyDown[256] table
// (0x00596A18) and by its double-click flag:
//   ctrl or double-click, no shift  0x0046FE41 SortAllUnits then applyNewSelect -> REPLACE
//   shift AND (ctrl or dbl)         0x0046FCAD SortAllUnits, then 0x0046FCDD
//                                   combineSelectionsLists -> ADD
//   shift alone, unit NOT selected   the inline ADD gate at 0x0046FD1B (below)
//   shift alone, unit IS selected    the inline REMOVE compaction at 0x0046FD77 -- no
//                                    movable gate, so shift-click REMOVE already works
//                                    for buildings in vanilla.
//   plain click                      0x0049AE40(1) + CMDACT_Select(1) directly;
//                                    SortAllUnits is NEVER called.
//
// THE CONSEQUENCE THAT SCOPES ANY CHANGE HERE: the only calls to SortAllUnits with a
// non-zero `clicked` are the two type-match sites above, so "clicked != 0" identifies the
// ctrl-click / double-click "select all of this type on screen" path exactly, with no
// state of our own.
#define SC_VA_CLICK_SELECT_HANDLER 0x0046FB40u
#define SC_VA_SORT_CALL_CLICK      0x0046FE41u  // ctrl/dbl, no shift
#define SC_VA_SORT_CALL_SHIFTCLICK 0x0046FCADu  // shift AND (ctrl or dbl)
#define SC_VA_KEYDOWN_TABLE        0x00596A18u  // BYTE[256], written by the window proc
#define SC_VA_KEYDOWN_SHIFT        0x00596A28u  // keyDown[VK_SHIFT]   -- 0x00596A18 + 0x10
#define SC_VA_KEYDOWN_CONTROL      0x00596A29u  // keyDown[VK_CONTROL] -- + 0x11
#define SC_VA_KEYDOWN_ALT          0x00596A2Au  // keyDown[VK_MENU]    -- + 0x12

// The double-click flag the click handler ANDs with "the clicked unit is already
// selected" (CSprite+0x0E & 0x08) at 0x0046FB6E. Written in exactly ONE function --
// 0x0046FF70, the mouse-event tick -- which sets it to 1 only for event type 6, which
// only the window procedure's WM_LBUTTONDBLCLK case (0x004D1D70 case 0x203) produces.
// So a POSTED WM_LBUTTONDBLCLK drives a real double click in an unattended run: the game
// does no timing of its own here, it trusts the message.
#define SC_VA_DOUBLE_CLICK_FLAG    0x0066FF58u  // u32
#define SC_VA_MOUSE_EVENT_TICK     0x0046FF70u

// THE FOUR CALL SITES OF unit_IsStandardAndMovable THAT REFUSE A BUILDING GROUP, by the
// address of the instruction AFTER the CALL -- i.e. the return address the detour sees.
// Each is quoted in research/building-groups.md 8.
//
//   shift-click ADD, inside the click handler (0x0046FD1B..0x0046FD5F): the existing
//     selection's FIRST unit at 0x0046FD24 and the CLICKED unit at 0x0046FD42, each
//     followed by a `JZ 0x0046fe95` that refuses.
//   combineSelectionsLists (0x0046F290), the shift+box / shift+ctrl merge: the NEW list's
//     first unit at 0x0046F2C6 and the EXISTING list's first (EDI[0]) at 0x0046F2E6; on
//     either failure it returns the EXISTING count and the merge never happens.
// Both callers of combineSelectionsLists copy activePlayerSelection into a local FIRST
// (0x0046FA40's 12-dword loop; 0x0046FC9A's `LEA EDI,[EBP-0x6c]` + `MOVSD.REP`), so EDI[0]
// is activePlayerSelection[0] at both sites -- which is what lets one rule ("what is the
// lead of the selection being extended?") cover all four.
#define SC_RET_MOVABLE_SHIFT_LEAD    0x0046FD2Cu
#define SC_RET_MOVABLE_SHIFT_CLICKED 0x0046FD49u
#define SC_RET_MOVABLE_COMBINE_NEW   0x0046F2CDu
#define SC_RET_MOVABLE_COMBINE_OLD   0x0046F2EDu

// unit_IsStandardAndMovable's own first two instructions (`MOV AX,[ECX + 0x64]` /
// `MOVZX EDX,AX`), the patch window a detour needs: seven bytes, two whole instructions,
// NEITHER PC-relative.
#define SC_MOVABLE_PATCH_LEN       7

// The client-side control-group recall's own copy of the gate (0x00496B40): it calls
// 0x0047B770 at 0x00496BE5, keeps an entry that passes, keeps a ONE-entry group whatever
// it holds (`CMP ESI,0x1 / JLE`), and drops the entry otherwise.
// So the engine will recall a single building, and would drop every building out of a
// group that held several. It never has to: hotkeySaveOrAdd fills the row from
// playersSelections, which the SIM gate (0x0049AF80) has already capped at one building.
// That is why the plugin does NOT write the engine's group row -- a row holding N
// buildings would be emptied by this test, and the receive-side recall (0x00496940)
// would COMPACT the row as it went, destroying the injection permanently.
#define SC_VA_HOTKEY_RECALL_GATE   0x00496BE5u

// ---------------------------------------------------------------------------
// HOW THE STATUS PANE DRAWS TEXT. Full evidence, with the listings, in
// research/status-pane-text.md. The two entries come from the default per-control-type
// handler tables dumped out of .rdata; everything under them is a CALL target read off
// the listing of the function above it. The chain:
//   dialog layer 2 draw 0x0041CB50 -> control's fxnUpdate (+0x2E) -> for a static-text
//   control the DEFAULT table entry SC_VA_STATIC_TEXT_UPDATE -> SC_VA_DRAW_CONTROL_TEXT ->
//   font + style + SC_VA_DRAW_STRING, with the string taken from control+0x14 (pszText).
// So a plugin control draws text by being type SC_CTRL_TYPE_LSTATIC with pszText pointing
// at its own buffer. It plots no pixels and adds no art.
// ---------------------------------------------------------------------------

// Update handler for control types 9/10/11, i.e. entries [9]/[10]/[11] of the default
// update table SC_VA_DEFAULT_UPDATE_TABLE. All three are the same nine instructions and
// differ only in the justification byte they store at SC_VA_TEXT_JUSTIFY (0x11/0x12/0x14
// respectively). Each returns without drawing anything when the control's pszText
// (+0x14) is null, then tail-calls 0x004EF870.
#define SC_VA_STATIC_TEXT_UPDATE   0x004EF9E0u  // type 9  (LSTATIC), justify 0x11
#define SC_VA_STATIC_TEXT_UPDATE10 0x004EF9C0u  // type 10, justify 0x12
#define SC_VA_STATIC_TEXT_UPDATE11 0x004EF9A0u  // type 11, justify 0x14
#define SC_VA_STATIC_TEXT_INTERACT 0x00419190u  // shared by all three (table [9..11])

// The draw itself. ECX = control, EAX = optional position override, two stack dwords are
// added to the position, RET 8. It picks the font from `control->flags & 0x4C00`
// (0x0400 -> the handle at 0x006CE0F4, which is what SC_CTRL_FONT_SMALLEST selects), sets
// a style index, takes the string from control+0x14, and takes BOTH the position and the
// clip box from the control's own bounds: position (bounds.left, bounds.top), clip
// (bounds.left, bounds.top, bounds.right, bounds.bottom).
#define SC_VA_DRAW_CONTROL_TEXT    0x004EF870u
#define SC_VA_SET_FONT             0x0041FB30u  // ECX = font handle; ECX = 0 restores
#define SC_VA_SET_TEXT_STYLE       0x0041F610u  // EAX = style index (2 normal, 5 disabled)
#define SC_VA_DRAW_STRING          0x004202B0u  // clips, then runs the glyph loop 0x004200D0
#define SC_VA_TEXT_JUSTIFY         0x006CE110u  // u8, set by the update handler per type
#define SC_VA_TEXT_FONT_HEIGHT     0x006CE111u  // u8, set by SC_VA_SET_FONT

// THE FONT'S OWN HEIGHT, readable before anything is drawn. SC_VA_SET_FONT copies it out
// of the font header (0x0041FB52 `MOV CL,[ECX+7]` -> 0x0041FB66 `MOV [0x006CE111],CL`),
// so the byte the clip rule is measured against is font+7, and 0x006CE0F4 is the handle
// the SC_CTRL_FONT_SMALLEST bit selects. Reading it directly is how a box is sized
// against the ENGINE's number instead of a constant right only on one install.
#define SC_VA_FONT_SMALLEST     0x006CE0F4u
#define SC_FONT_OFF_HEIGHT      0x07u

// THE RULE A BOX HAS TO SATISFY, off SC_VA_DRAW_STRING's own clip test: the string is
// drawn only when
//     left >= clip.left && top >= clip.top && left <= clip.right &&
//     top + fontHeight <= clip.bottom
// and the clip box is the control's own bounds. A box only as tall as the font's advance
// therefore draws NOTHING, silently -- which is why SC_QIND_BOX_H is generous.

// The per-frame HUD driver (hud-selection-row.md 4.1) -- it calls updateSelectedUnitData,
// the command-card update 0x004599A0, then the status dispatcher 0x00458120 at 0x004D940F.
// sc_queueind detours THIS and runs after the original, so its control is re-shown after
// the engine's own hide-all sweep in both the single-unit and multi-select branch. Patch
// window 5 bytes / 1 instruction (MOV AL,[0x0059723C]) -- absolute, so reloc-safe.
#define SC_VA_STAT_DISPLAY_DRIVER  0x004D93F0u

// WHERE A CONTROL'S fxnUpdate IS CALLED FROM, and onto WHAT.
//
// Graphic layer 2's callback 0x0041CB50 (research/renderer-viewport.md) walks the global
// dialog list 0x006D5E34 and calls SC_VA_DIALOG_DRAW_WALK per visible dialog. That function
// climbs a child to its parent dialog (0x0041C09C), points the current render target
// 0x006CF4A8 at the DIALOG's surface descriptor `dlg + 0x36` (0x0041C1D9..0x0041C1DF), and
// only then calls the control's fxnUpdate (0x0041C1E5). So a control's text lands in its
// DIALOG's own 8-bit surface, and the descriptor the draw clips against is at dlg+0x36,
// restored to the previous target on the way out.
#define SC_VA_DIALOG_DRAW_WALK     0x0041C080u
#define SC_VA_DIALOG_LAYER_DRAW    0x0041CB50u
#define SC_VA_RENDER_TARGET        0x006CF4A8u  // {u16 w, u16 h, u8* bits}*

// The surface descriptor itself: {u16 w, u16 h, u8* bits}, 8 bits per pixel, at the offset
// 0x0041C080 installs (above). The allocator 0x004C35F0's own decompile puts it 0x2A
// earlier instead, which is a register the decompiler could not resolve rather than a
// fact, so the reader tries the evidenced offset FIRST, falls back to the other, and says
// which it used. Nothing but a diagnostic depends on the answer.
#define SC_BINDLG_OFF_SURFACE      0x36u   // {w, h, bits} -- 0x0041C1D9, load-bearing
#define SC_BINDLG_OFF_SURFACE_ALT  0x0Cu   // {w, h, bits} -- 0x004C35F0's own arithmetic
#define SC_SURFACE_OFF_W           0x00u   // u16
#define SC_SURFACE_OFF_H           0x02u   // u16
#define SC_SURFACE_OFF_BITS        0x04u   // u8*

// ---------------------------------------------------------------------------
// THE DIALOG DIRTY-MARK CLIP BOX.
// updateControlInner (0x0041C200) -- the ONE function that adds a dialog rect to the
// layer-2 dirty region (storm region 0x006D5E2C, consumed by 0x0041CB50) -- aligns the
// rect to 16px and clamps it against these four globals (0x0041C21B, 0x0041C24D,
// 0x0041C240, 0x0041C25C). Each is referenced by EXACTLY that one instruction in all of
// .text (byte-scan) -- NO WRITER EXISTS. They are link-time .data constants
// {0, 0, 640, 480}, read straight out of the file image. So no dialog repaint can ever be
// MARKED past x=639, and moving a dialog's bounds past it changes nothing on screen:
// measured, StatBtn moved to 656..799 drew NOTHING while StatRes -- whose overlap with the
// ever-repainting playfield rides a different dirty path -- showed its number at x~760.
// Because no writer exists, widening the max-x once is a stable, one-shot data patch with
// no engine re-assertion to fight (AGENTS.md § "Engine-owned flags") -- sc_console does it
// while the console-edge move is armed, and restores it on remove.
//
// The sibling box at 0x0051A15C..0x0051A168 = {0, 0, 639, 479} is the DRAW-time clip in
// 0x0041C080, in ROOT-RELATIVE coordinates -- a 144- or 420-wide console dialog never
// reaches it, so it is recorded, not patched.
#define SC_VA_DLG_DIRTY_CLIP_X0    0x0051A16Cu  // 0
#define SC_VA_DLG_DIRTY_CLIP_Y0    0x0051A170u  // 0
#define SC_VA_DLG_DIRTY_CLIP_X1    0x0051A174u  // 640 stock
#define SC_VA_DLG_DIRTY_CLIP_Y1    0x0051A178u  // 480 stock

// u8 -- client_selection_changed (binary-selection-map.md 7 window table). The stat
// display driver's FIRST instruction reads it (0x004D93F0 MOV AL,[0x0059723C]) and, when
// set, calls updateSelectedUnitData (0x004C38B0), which copies activePlayerSelection into
// clientSelectionGroup, recounts clientSelectionCount, elects activePortraitUnit and
// refreshes the status area. The plugin's select aid sets it after the CMDACT_Select
// funnel so the engine's own writer completes the client half exactly as a real click
// does (measured: without it, active=1 sim=1 but client=0 and the card stays empty).
#define SC_VA_CLIENT_SEL_CHANGED   0x0059723Cu


#endif // SC_ADDRESSES_H

// --- the GetCursorPos import -------------------------------------------------------
// The edge-scroll 0x004D12A0 reads the OS cursor through this import slot and compares
// the raw point with the screen's edges (scroll.*.trigger sites). Off-screen the OS
// cursor is the user's real mouse, or wherever the game's own ClipCursor pushed it, and
// under cnc-ddraw the slot already points at that helper's translation of it; a run
// driven by posted moves needs the engine to see its own cursor instead (sc_marktrace).
#define SC_VA_IMPORT_GETCURSORPOS  0x004FE2DCu

// --- the image-rect mark ----------------------------------------------------------
// 0x0042D280 marks the dirty cells under a pixel rect {s32 x1, y1, x2, y2} at ESI --
// the image module's own writer (animation, movement, show/hide) -- by filling the
// grid rows itself, never through the marker 0x0041E0D0. A trace of the marker alone
// therefore misses every sprite mark; sc_marktrace hooks this one beside it.
#define SC_VA_IMAGE_MARK           0x0042D280u
