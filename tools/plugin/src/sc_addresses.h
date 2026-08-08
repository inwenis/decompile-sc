// sc_addresses.h -- StarCraft 1.16.1 selection-subsystem static addresses.
//
// Every constant here is a *preferred-image-base* virtual address (StarCraft.exe's
// PE ImageBase is 0x00400000, see research/pe-anatomy.md). Nothing dereferences
// these directly: the plugin converts each one to a runtime address with
//
//     runtime = actualModuleBase + (staticVA - SC_PREFERRED_IMAGE_BASE)
//
// so a relocated/ASLR'd load is handled rather than assumed away.
//
// Provenance for the observer's addresses is research/binary-selection-map.md; the
// exact section is quoted in the comment above each constant. The selection arrays
// and counters additionally have per-instruction rows in the committed evidence table
// research/data/selection-xrefs.tsv. The three player-id VAs below do NOT -- they
// have no rows in that TSV and come from the map's section 7 prose alone, which is
// also why the plugin logs all three rather than picking one. Types come from the
// same document (clientSelectionCount resolved to u8 there -- all 23 accesses in
// the binary are byte-width, no dword access exists).
//
// The COMMAND-PATH block at the bottom was derived by task 011 from this binary
// (Ghidra headless, tools/ghidra/specs/hook-targets.spec); every claim there is
// written up with its evidence in research/command-path.md. Nothing in that block
// is inherited from public prior art without being re-derived here.

#ifndef SC_ADDRESSES_H
#define SC_ADDRESSES_H

#include <windows.h>

// PE ImageBase of StarCraft.exe 1.16.1 (research/pe-anatomy.md).
#define SC_PREFERRED_IMAGE_BASE 0x00400000u

// ---------------------------------------------------------------------------
// Selection state (task 008; research/binary-selection-map.md)
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

// Active player id. binary-selection-map.md 7 note 7 warns that THREE distinct
// player-id globals are in play in the selection subsystem and conflating them
// produces bugs, so the plugin logs all three and lets the reader compare.
#define SC_VA_ACTIVE_PLAYER_ID    0x0051267Cu  // named by selection-cap.md 2.2
#define SC_VA_PLAYER_ID_512688    0x00512688u  // used in selectSingleUnitFromID
#define SC_VA_PLAYER_ID_512678    0x00512678u  // GPTP ACTIVE_NATION_ID

#define SC_SELECTION_SLOTS 12
#define SC_MAX_PLAYERS     8

// ---------------------------------------------------------------------------
// CUnit layout (offsets inherited from GPTP; each one is USED by an instruction
// this task decompiled, which is corroboration rather than independent derivation
// -- binary-selection-map.md 8 "Inherited and used as-is" makes the same caveat).
// ---------------------------------------------------------------------------

#define SC_CUNIT_SIZE            0x150u  // 336; measured live in
                                         // research/runtime-selection-observations.md 3.5
#define SC_CUNIT_OFF_SPRITE      0x0Cu   // CSprite*; read as [unit+0x0C] by every function
                                         // in research/selection-circles.md 2
#define SC_CUNIT_OFF_PLAYER      0x4Cu   // u8 owning player
#define SC_CUNIT_OFF_UNIT_ID     0x64u   // u16 unit type id
#define SC_CUNIT_OFF_UNIQUENESS  0xA5u   // u8, the tag's staleness check

// u8 -- the unit's CURRENT (main) ORDER id, immediately after the owning player at 0x4C.
// Derived by task 015 from the receive-side handlers in this binary, which read it to
// avoid re-issuing an order a unit is already on: the 0x25 handler (0x004C1F10) issues
// order 0x63 and skips a unit whose [+0x4D] is already 0x63; 0x26 (0x004C1E80) does the
// same with 0x62; 0x2C (0x004C1FA0) with 0x74. The issue-order helper 0x004754F0
// switches on it with order-shaped cases. THIS is the field that changes when a unit is
// told to move, stop or hold.
#define SC_CUNIT_OFF_ORDER_ID    0x4Du

// u8 -- the SECONDARY order id, which runs alongside the main one. The 0x22 handler
// (0x004C0660) sets it to 0x6E and clears the order-target fields beside it, and
// 0x00491B30 (from the 0x21 handler) sets it to 0x6D after deducting the unit's energy --
// a cloak, which is exactly the kind of thing that persists while a unit does something
// else. Logged next to the main order so a command that changes only one of the two is
// still visible.
#define SC_CUNIT_OFF_ORDER2_ID   0xA6u

// u32 -- unit flags. Bit 0x10 is the burrowed/submerged state: the Stop handler
// (0x004C2190) refuses a unit with it set unless the unit's type is 0x67, the one type
// that acts while burrowed, and the Right Click applier (0x004560D0) picks a different
// behaviour table for exactly that combination. READ ONLY, same as the order id.
#define SC_CUNIT_OFF_FLAGS       0xDCu
#define SC_UNIT_FLAG_BURROWED    0x10u

// ---------------------------------------------------------------------------
// SELECTION CIRCLES -- derived by task 014 from StarCraft.exe 1.16.1 itself.
// Full evidence, with disassembly, in research/selection-circles.md.
//
// NOTE the offsets below are NOT the ones BWAPI's CSprite.h publishes. BWAPI puts
// selectionIndex at 0x03 and flags at 0x06; this binary uses 0x0B and 0x0E, because
// its CSprite begins with the two linked-list pointers. research/selection-cap.md
// 2.4 already quoted 0x0B for selectionIndex from prior art; 0x0E for flags is new
// here, and both are now read off instructions in this binary rather than inherited.
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
// by the click handler at 0x0046FB40, which builds the on-screen rectangle it searches
// as `{ left, top, left + 0x280, top + 400 }` -- i.e. 640 wide, and these two are its
// origin. Used only to log where a circled unit is on screen, so an automated test can
// aim a click at one; nothing in the feature itself depends on them.
#define SC_VA_SCREEN_LEFT 0x0062848Cu  // u16 (the binary reads the low half)
#define SC_VA_SCREEN_TOP  0x006284A8u  // u16

// Sprite flag bits, confirmed against this binary (selection-circles.md 3):
//   0x01 -- a selection-circle image (id 0x231..0x23A) is attached to this sprite.
//           0x004975D0 clears exactly this bit and frees exactly that image.
//   0x08 -- "selected". 0x004E6180 sets it together with selectionIndex; 0x00497620
//           clears it. IT IS THE GATE ON ALL FOUR selectionIndex READS IN THE BINARY:
//           0x0046FD77 and 0x0049F7B3 use the value as a memmove offset into a 12-entry
//           STACK array (no value is safe there for a unit outside the engine's 12),
//           while 0x0049F00B and 0x0049F8B6 save it and re-attach with
//           0x004E6180(saved). Leaving this bit clear is what puts our units out of
//           reach of all four. Table and reasoning: research/selection-circles.md 4.
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
// WHICH END OF THE LIST DRAWS FIRST IS NOT ESTABLISHED. An earlier version of this
// comment asserted "so it draws over the unit's own images", which is unevidenced and
// probably backwards -- the selection circle plainly renders UNDER the unit on screen,
// and the health bar (linked at the FIRST-overlay end by 0x004D6420) renders over it.
// Nothing in this task decompiled the renderer's walk, so the ordering is left as an
// open question rather than guessed at (research/selection-circles.md 7). A future
// health-bar task must settle it before relying on either end.
#define SC_VA_SPRITE_ADD_SEL_CIRCLE 0x004D7070u

// ECX = CSprite*, no stack arguments, RET. If flag 0x01 is set, clears it, finds the
// image whose id is in 0x231..0x23A and frees it. This is the engine's own
// remove-just-the-circle primitive (it is the whole of the invincible-unit deselect
// path), which is exactly what a plugin that never sets flag 0x08 needs.
#define SC_VA_SPRITE_REMOVE_SEL_CIRCLE 0x004975D0u

// EAX = CUnit**, __stdcall(u32 count), RET 4. The client-side "replace the whole
// selection" funnel: it detaches the selection graphics of every unit currently in
// activePlayerSelection, then attaches them to the new list. 10 callers, covering the
// drag box, every click path, and control-group recall -- which makes its ENTRY the
// one place a plugin can drop its own extra circles before the engine re-attaches.
#define SC_VA_CREATE_NEW_UNIT_SELECTIONS 0x0049AE40u

// The engine's own per-unit primitives. NOT called or hooked by this plugin -- listed
// because research/selection-circles.md 2 quotes them and because a future task that
// wants the HP bar as well will need them.
#define SC_VA_UNIT_SELECT_GRAPHICS   0x004E6180u  // EAX = CUnit*, __stdcall(u8 slot)
#define SC_VA_UNIT_DESELECT_GRAPHICS 0x004E6290u  // EAX = CUnit*

// ---------------------------------------------------------------------------
// COMMAND PATH -- derived by task 011 from StarCraft.exe 1.16.1 itself.
// Full evidence, with disassembly, in research/command-path.md.
// ---------------------------------------------------------------------------

// __fastcall(ECX = const void* cmdBytes, EDX = size_t len) -- appends one command
// to the outgoing turn buffer. THE funnel: every CMDACT_* builder in the binary
// reaches the wire through this one function (117 references). It flushes through
// 0x00485A40 when the command would not fit. command-path.md 1.
#define SC_VA_QUEUE_COMMAND 0x00485BD0u

// The turn buffer queueCommand appends into, and its running byte count. Both were
// inherited from BWAPI Offsets.h:75-76 and are re-confirmed here by the instructions
// inside queueCommand itself (`&DAT_00654880 + DAT_00654aa0` as the copy
// destination). command-path.md 1.
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

// Mixed convention: EAX = current count, ECX = CUnit** out12,
// stack [+4] = CUnit* unit, [+8] = CUnit* clicked, RET 8.
// Called once for EVERY unit that passed all selection filters but did not fit in
// the 12 slots -- which makes it the one place in the engine where the units the
// cap is about to discard are individually visible. command-path.md 3.
#define SC_VA_SORT_OVERFLOW 0x0046F040u

// Unit-tag encoding, read off three independent instruction sequences in this
// binary (CMDACT_Select 0x004C0919, the Right Click builder 0x004C03A0, the
// Targeted Order builder 0x004C0323 -- all three compute it identically):
//
//     index = (unitPtr - 0x0059CCA8) / 0x150 + 1        // 1-based
//     if (index > 0x6A4) tag = 0                        // CMP ECX,0x6a4 / JBE
//     else tag = (unit[0xA5] << 11) | index
//
// This settles the open question in research/runtime-selection-observations.md 3.5,
// which could only say the community base 0x0059CCA8 was "strong support ...
// but unverified prior art". It is in the binary, three times. command-path.md 4.
#define SC_VA_UNIT_ARRAY_BASE 0x0059CCA8u
#define SC_MAX_UNIT_INDEX     0x6A4u   // inclusive; index 0 and >0x6A4 encode as tag 0

// Wire command ids used by the fan-out. The full 46-entry table this came from is
// in research/command-path.md 5; these are the three the plugin acts on by name.
#define SC_CMD_SELECT        0x09u
#define SC_CMD_SELECT_ADD    0x0Au
#define SC_CMD_SELECT_REMOVE 0x0Bu
#define SC_CMD_HOTKEY        0x13u
#define SC_CMD_RIGHT_CLICK   0x14u
#define SC_CMD_TARGETED_ORDER 0x15u

#endif // SC_ADDRESSES_H
