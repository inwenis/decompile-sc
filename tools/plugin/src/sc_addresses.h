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
// Provenance for each address: research/binary-selection-map.md and its committed
// evidence table research/data/selection-xrefs.tsv. Types come from the same
// document (clientSelectionCount resolved to u8 there -- all 23 accesses in the
// binary are byte-width, no dword access exists).

#ifndef SC_ADDRESSES_H
#define SC_ADDRESSES_H

#include <windows.h>

// PE ImageBase of StarCraft.exe 1.16.1 (research/pe-anatomy.md).
#define SC_PREFERRED_IMAGE_BASE 0x00400000u

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

#endif // SC_ADDRESSES_H
