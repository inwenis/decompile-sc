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
// CONTROL GROUPS -- derived by task 021 from StarCraft.exe 1.16.1 itself.
// Full evidence, with decompiles, in research/control-groups.md; the committed
// instruction table is research/data/hotkey-xrefs.tsv.
// ---------------------------------------------------------------------------

// u32[8][18][12] -- the control-group store, holding StoredUnit TAGS
// ((uniqueness << 11) | unitIndex), not CUnit*. Shape confirmed twice over in
// binary-selection-map.md 3.5 (a 1728-dword REP STOSD, and the 864/48 strides) and
// again here by hotkeySaveOrAdd's own row arithmetic, `(group + activePlayerId*0x12)
// * 0xc` dwords off this base (0x004965E9..0x004965F5).
//
// Groups 0..9 are the Ctrl+N groups; 10..17 are the engine's OWN alt-click
// recent-selection ring (binary-selection-map.md 5.2: CMDRECV_Select picks an LRU
// slot and `ADD AL,0xa` before saving). The plugin mirrors 0..9 and never touches
// 10..17.
//
// This plugin only ever READS this array (the new-game detection in sc_fanout's
// shadow-group block). Nothing here writes it.
#define SC_VA_SELECTION_HOTKEYS 0x0057FE60u
#define SC_HOTKEY_GROUPS_PER_PLAYER 18
#define SC_HOTKEY_SLOTS_PER_GROUP   12

// u16[8][8] -- when each recent-selection slot was last used, the LRU key
// 0x00496560 scans backwards over. Cleared beside the hotkey array by both
// resets. Listed for completeness; the plugin does not read it.
#define SC_VA_RECENT_SELECTION_TIMES 0x0063FE40u

// The two globals implementing 500 ms double-tap-to-centre, immediately behind
// clientSelectionGroup2 (binary-selection-map.md 3.2). Every 0x13-emitting site in
// the key dispatcher writes 0xFF to the group id; listed so a reader of that
// dispatcher can recognise them. Not read or written here.
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
// The key dispatcher 0x004846E0 carries three families of ten sites, one per action:
// ten `13 00 g` (via the shared tail at 0x004849EB, BL = 0), ten inline `13 02 g`
// (0x004848A2 and its nine siblings), and ten recall sites that call 0x004967E0 then
// 0x00496B40(g).
#define SC_HOTKEY_ASSIGN 0
#define SC_HOTKEY_RECALL 1
#define SC_HOTKEY_ADD    2

// The engine's own functions on this path. NOT hooked or called by this plugin --
// the shadow-group feature adds no hook at all -- but every claim the code makes
// about ordering names one of them, so they are recorded here with the rest.
#define SC_VA_HOTKEY_CLEAR            0x004965A0u  // REP STOSD over both arrays
#define SC_VA_HOTKEY_SAVE_OR_ADD      0x004965D0u  // the store; arg 0 = add, 1 = assign
#define SC_VA_HOTKEY_DOUBLE_TAP       0x004967E0u  // centre the view on a re-tap
#define SC_VA_HOTKEY_RECALL_RECV      0x00496940u  // receive side: writes playersSelections
#define SC_VA_HOTKEY_KEY_HANDLER      0x00496B40u  // client side: 0x0049AE40 then CMDACT_HotkeyUnit
#define SC_VA_CMDACT_HOTKEY_UNIT      0x004C07B0u  // builds and queues the 3-byte 0x13
#define SC_VA_CMDRECV_HOTKEY          0x004C2870u  // action dispatch, group guard `CMP AL,0x12`
#define SC_VA_GAME_START_HOTKEY_CLEAR 0x004EEC30u  // the game-start reset

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

// u16 -- the unit's ENERGY, in the engine's 1/256 fixed point (a 200-energy caster
// reads 0xC800). Named by task 015 from 0x00491B30, the deduct the 0x21 handler calls;
// task 022 read that function's own instructions rather than inheriting the claim:
// it compares `(u16)(cost * 0x100) <= *(u16*)(unit + 0xA2)` and then does
// `*(short*)(unit + 0xA2) += cost * -0x100`. A field compared against a cost and then
// reduced by exactly that cost is the resource the ability spends.
// research/ability-semantics.md 3.
#define SC_CUNIT_OFF_ENERGY      0xA2u

// u8 -- the STIM TIMER, in game frames. Derived by task 022 from the 0x36 handler
// 0x004C2F30 in THIS binary (research/ability-semantics.md 2), disassembly quoted
// there:
//     0x004C2FE0  MOV CL,byte ptr [ESI + 0x115]
//     0x004C2FE6  MOV AL,0x25
//     0x004C2FEA  JNC skip                      ; already >= 0x25, leave it alone
//     0x004C2FEC  MOV byte ptr [ESI + 0x115],AL ; else set it to 0x25
// A field the ability sets to a fixed duration, refreshed rather than stacked, written
// immediately after the unit pays the ability's HP cost. 16 instructions in the whole
// binary touch this displacement (work/scratch/022/field-115.tsv, FieldSweep) and the
// corroborating pair is 0x00492F70, which reads it, decrements and writes it back --
// i.e. it ticks down. READ ONLY here, same as the order id.
#define SC_CUNIT_OFF_STIM_TIMER  0x115u
#define SC_STIM_TIMER_FRAMES     0x25u   // what 0x004C2F30 writes

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

// ---------------------------------------------------------------------------
// HUD SELECTION ROW -- derived by task 017 from StarCraft.exe 1.16.1 itself.
// Full evidence, with decompiles and the creation chain, in
// research/hud-selection-row.md; committed instruction tables in
// research/data/hud-*.tsv. Nothing in this block is inherited without being
// re-derived against this binary.
// ---------------------------------------------------------------------------

// No arguments, returns void. THE per-frame status-area dispatcher: the single
// entry the HUD driver 0x004D93F0 calls each frame, branching portrait-null /
// single-unit / multi-select (hud-selection-row.md 4.2). sc_hudrow detours THIS
// (not the multi-select act/cond pair) so it can restore the row to stock even
// when a shadow click drops the selection to one unit and the engine would take
// its single branch. Patch window 5 bytes / 1 instruction (MOV EAX,[0x00597248]),
// reloc-safe; one caller (HookProbe, work/scratch/hud/hookprobe/).
#define SC_VA_STAT_DATA_UPDATE 0x00458120u

// The multi-select layout ("act") and refresh-condition ("cond") the dispatcher
// calls; sc_hudrow re-implements their effect for a page rather than detouring
// them, but keeps the addresses for evidence (hud-selection-row.md 4.2).
#define SC_VA_UNITSTAT_ACT_SELECTION  0x00425960u
#define SC_VA_UNITSTAT_COND_SELECTION 0x00424660u

// Unit* -- the active portrait unit; the dispatcher's first test (portrait NULL ->
// hide the whole status area). sc_hudrow reads it to decide whether to page.
#define SC_VA_ACTIVE_PORTRAIT_UNIT 0x00597248u

// Generic dialog primitives (GPTP unit_stat_selection.cpp helpers; conventions
// verified against the decompiled callers in this binary):
#define SC_VA_SHOW_CONTROL   0x004186A0u  // ESI = BinDlg*
#define SC_VA_HIDE_CONTROL   0x00418700u  // ESI = BinDlg*
#define SC_VA_UPDATE_CONTROL 0x0041C400u  // EAX = BinDlg*

// __fastcall(ECX = BinDlg* control, EDX = event) -> int. The wireframe button's
// interact handler; all 12 buttons point here via the 44-entry table at 0x00504AF0
// (hud-selection-row.md 3). sc_hudrow WRAPS the per-control pointer (control+0x2A)
// with a thin shim and tail-calls this address -- the code itself is never patched.
#define SC_VA_WIREFRAME_BTN_INTERACT 0x004583E0u

// The statdata module's globals (hud-selection-row.md 2):
#define SC_VA_STATDATA_DIALOG 0x0068C1F0u  // BinDlg* -- the whole status-area dialog
#define SC_VA_STAT_DIRTY      0x0068C1F8u  // u8 -- redraw-needed flag the dispatcher consumes
#define SC_VA_STAT_ALL_HIDDEN 0x0068C1E5u  // u8 -- "children currently hidden" state

// Default per-control-type handler tables the .bin relocator (0x004194E0) assigns
// from; sc_hudrow's indicator control takes its handlers from the same tables, so
// it is drawn by exactly the code a loaded control would be.
#define SC_VA_DEFAULT_INTERACT_TABLE 0x005014ACu
#define SC_VA_DEFAULT_UPDATE_TABLE   0x00501504u

// BinDlg field offsets. Those marked "hud 2" are proven by an instruction cited
// in hud-selection-row.md 2 (read out of THIS binary). Those marked "GPTP" are
// inherited from GPTP SCBW/structures.h and used as-is -- NOT independently
// re-derived here; they are not referenced by the sweep, so this block states
// their true provenance rather than overclaiming.
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
                                          //   only used to zero a plugin-owned scratch
                                          //   BinDlg -- never to stride a game array.

#define SC_CTRL_FLAG_DRAWN   0x1u    // set once drawn; act sets it before updateControl
#define SC_CTRL_FLAG_VISIBLE 0x8u    // hud 2 (0x0045845D TEST [ctrl+0x18],0x8)
// CTRL_FONT_SMALLEST -- BWAPI BW/Dialog.h:17. The smallest of the font-size flags,
// so the indicator text fits the row's top edge.
#define SC_CTRL_FONT_SMALLEST 0x400u
// Control type of a left-aligned static text control. BWAPI BW/Dialog.h ctrls
// enum: cLSTATIC = 9. Verified at runtime before use: sc_hudrow reads the default
// interact/update table entries for type 9 and refuses to splice the indicator if
// either is null (i.e. the engine has no handler for that type in this build).
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
// dwUser sub-code of a completed click, where 0x004583E0 turns the button's
// statUser unit into a Select. Read out of this binary: 0x004583E0's dwUser switch
// (jump table at 0x0045849C, work/scratch/hud/binder-listing.tsv) sends case 2 to
// 0x0045844E -> CALL 0x00458220 (StatusScreenButton, the select). BWAPI
// BW/Dialog.h names it BW_USER_ACTIVATE = 2.
#define SC_USER_ACTIVATE 2

// CUnit fields the row reads. hitpoints at +0x08 is read for the DEATH signal;
// it is the field the engine's DAMAGE primitive 0x004797B0 zeroes on a kill
// (research/command-opcodes.md 6), so a damage-death reads 0 here. id at +0x64.
#define SC_CUNIT_OFF_HITPOINTS 0x08u

// The player unit list -- per-player list heads at 0x006283F8, and the CUnit
// prev/next links the engine threads them on. Derived by task 017 from the unit
// (re)init 0x004A0320 (decompiled): it sets [unit+0x68]=0, [unit+0x6C]=head,
// [head+0x68]=unit, head=unit -- a head-insert doubly linked list, indexed by the
// unit's owning player. The removal path 0x004A0740 UNLINKS a unit that is removed
// from play, so a unit NOT reachable from playerUnitList[player] via +0x6C has been
// removed (killed-and-not-yet-recycled, trigger RemoveUnit, archon-consumed). Note:
// a TRANSPORT-loaded unit stays list-linked (the engine walks the list for supply,
// loaded units included) and a MIND-CONTROLLED unit relinks under its new owner, so
// both remain reachable -- and both are fine to hand to the engine's Select: they
// are live, identity-correct CUnit*s that vanilla can select. The array size is not
// evidenced here (vanilla convention is one entry per player incl. neutral); the
// gate reads only indices < SC_MAX_PLAYERS (8), which is fail-closed for any size.
#define SC_VA_PLAYER_UNIT_LIST 0x006283F8u
#define SC_CUNIT_OFF_LIST_PREV 0x68u
#define SC_CUNIT_OFF_LIST_NEXT 0x6Cu
#define SC_MAX_UNITS_WALK      2000   // loop bound: never trust a game list to terminate

// The engine's list of ACTIVE dialogs (task 027). Head pointer; each entry is a
// BinDlg, threaded on the same +0x00 "next" link every dialog walk in this file uses.
//
// Evidence, out of THIS binary (Ghidra listing of the event dispatcher 0x00419FD0,
// the function every posted input event goes through -- 0x004D1AE0's mouse-move
// dispatch and the window procedure's key cases all call it):
//
//     0041a007  PUSH EDI
//     00419ffd  MOV ECX,dword ptr [0x006d5e34]   ; <- the head
//     0041a005  JZ ...                           ; empty list -> nothing to offer
//     0041a008  MOV EDI,dword ptr [ECX]          ; next (SC_BINDLG_OFF_NEXT)
//     0041a00c  CALL dword ptr [ECX + 0x2a]      ; interact (SC_BINDLG_OFF_INTERACT)
//     0041a019  JNZ 0x0041a008                   ; ... until the link is null
//
// i.e. the dispatcher offers each event to every dialog in this list in turn, using
// exactly the +0x00/+0x2A layout sc_hudrow already relies on. The plugin only READS
// it (name, bounds and the same for each dialog's controls) so a suite can find the
// in-game tips dialog and its OK button instead of clicking a hardcoded point.
#define SC_VA_DIALOG_LIST 0x006D5E34u
#define SC_MAX_DIALOGS_WALK 16        // loop bound, same reason as SC_MAX_UNITS_WALK
#define SC_MAX_CTRLS_WALK   64

#endif // SC_ADDRESSES_H
