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
#define SC_CUNIT_OFF_PLAYER      0x4Cu   // u8 owning player
#define SC_CUNIT_OFF_UNIT_ID     0x64u   // u16 unit type id
#define SC_CUNIT_OFF_UNIQUENESS  0xA5u   // u8, the tag's staleness check

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
