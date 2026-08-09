---
from: 021
to: conductor
sent: 2026-08-08T23:41:06Z
subject: Design: plugin-side shadow control groups (option a) - proceeding
---

## What the binary says (evidence, StarCraft.exe 1.16.1 AD6B58B2…88C6A46, Ghidra 12.1.2)

**Storage.** `selectionHotkeys` `0x0057FE60`, `[8][18][12]` u32 `StoredUnit` tags
(`(uniqueness << 11) | unitIndex`), 6912 bytes. Groups 0..9 are the Ctrl+N groups, 10..17
the alt-click recent ring. Confirmed here from `hotkeySaveOrAdd`'s own index arithmetic:
`(group + activePlayerId*0x12) * 0xc` dwords off the base.

**Exactly 7 functions touch it** (41 instructions; my XrefSweep reproduces
binary-selection-map.md 2.1 exactly): `0x004965A0` clear, `0x004965D0` store,
`0x004967E0` double-tap centre, `0x00496940` receive-side recall, `0x00496B40` client-side
recall, `0x00496D30` selectSingleUnitFromID, `0x004EEC30` game-start clear.
**No save/load function is among them** -- control groups are memory-only in vanilla too.

**The 0x13 wire command is 3 bytes**, built at `0x004C07BF`:
`[0]=0x13 [1]=action [2]=group`. Action `0` = ASSIGN (Ctrl+N), `1` = RECALL (N),
`2` = ADD. The key dispatcher `0x004846E0` carries three families of ten sites, one per
group: ten `13 00 g`, ten `13 02 g`, and ten recall sites (`CALL 0x004967E0` then
`CALL 0x00496B40(g)`). **So shift-add IS supported by the engine** -- the exact key
combination is not established statically (the dispatch is a jump table on Blizzard's own
composite key code) and I will answer it in game.

**Per-group capacity is 12, twice over**: the store loop returns at `iVar3 > 11`, and its
source `playersSelections[player]` is itself 12 slots.

## Design choice: (a) plugin-side shadow groups -- ten of them, mirroring the engine's ten

Reasoning, and why (b) is out:

1. **(b) widening in place is refuted, not merely expensive.** `binary-selection-map.md`
   3.5 already showed only ~1 KB of unclaimed space behind the array -- doubling it needs
   6912 more. On top of that the store, recall and centre paths are hand-unrolled 6-way with
   the 12 baked into the unroll, and 2.2's stride sweep lists 6 encoded x12 row strides
   for this array alone. It is not bounds-driven code.
2. **(a) needs NO new engine hook and NO new patch site.** The whole feature lands inside the
   existing `queueCommand` hook, because the client emits `13 <action> <group>` *after* it has
   already done the client-side work:
   - store: `13 00/02 g` is queued inline by the key dispatcher; our shadow list is current at
     that instant -> snapshot / union it into plugin group `g`.
   - recall: `0x00496B40` calls `CreateNewUnitSelectionsFromList` (`0x0049AE40`) **first**
     (that is what fills `activePlayerSelection` `0x006284B8` with the engine's new <=12), and
     only then queues `13 01 g`. So at hook time the engine's post-recall visible 12 is
     readable, and I rebuild the shadow list as (plugin group `g` minus visible) + visible.
   This replaces today's "drop the shadow list on 0x13" (sc_fanout.cpp:753), which was written
   deliberately because a recall rebuilds the selection outside `CMDACT_Select`. It does -- via
   `0x0049AE40`, which is the seam that makes the fix possible.

## Where units 13..N live, and the selectionIndex/flag-0x08 hazard

They live in **plugin memory only**, as the same `(CUnit*, CUnit+0xA5, CUnit+0x4C)` triple the
shadow list already uses -- never in `selectionHotkeys`, never in `playersSelections`, never in
`activePlayerSelection`. Nothing this task adds writes a single byte of engine selection state.

That is what keeps it clear of the hazard: `CSprite::selectionIndex` (+0x0B) is only ever read
behind sprite flag `0x08`, the engine sets `0x08` itself inside `0x004E6180` for exactly the
units it puts in `activePlayerSelection`, and units 13..N are never in that array. Our circles
keep setting flag `0x01` alone, as task 014 established. A recall reaches units 13..N only
through the existing fan-out emit path, i.e. as wire tags in a `Select(<=12)`.

## The staleness answer (save/load, "safe, not merely unlikely")

Plugin groups are memory-only, so a load can leave them stale. Two independent gates, not a
probability argument:

1. every entry is re-run through **task 020's five-term liveness gate** at recall -- reused, not
   reinvented;
2. a **containment check**: the engine's own post-recall list must be a subset of the plugin
   group. That is an invariant the store/add paths maintain by construction (we store a
   superset of what the engine stores), so a violation *means* the group is stale or foreign ->
   drop it and fall back to today's behaviour (shadow = the engine's 12). After a load the
   engine's groups are either empty (in which case `0x00496B40` returns before queueing
   anything and our recall path never runs at all) or hold units of the loaded game, which
   cannot be contained in a group from a different session.

Proceeding on this now; redirect me if you disagree.
