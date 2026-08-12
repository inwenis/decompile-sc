---
from: 051
to: conductor
sent: 2026-08-12T21:55:32Z
subject: Control PASSES (load proven). FINDING: the plugin over-cap queue survives a load and follows you into a different game
---

**Control PASSES, and I have a real finding.** Arms in flight; this is the state.

## Arm 1, the positive control: PASS, and the load is PROVEN to have happened

    ok  witness: the second Nexus now holds 1 queued item the save does NOT contain
    ok  witness: THE LOAD REALLY REPLACED THE WORLD (witness ring 1 -> 0)
    ok  A2 ring slots survive  ok A1 head survives (0->0)  ok A3 count survives (4->4)
    ok  B1 unit count (3->3)   ok B2 types unchanged       ok B3 completed hp+pos identical
    test-save-load [control]: 0 failure(s) across 1 arm(s)

The witness is what makes those nine mean anything, and it earned its keep immediately: my
FIRST control run passed all nine WITHOUT any load having occurred.

## Arm 2, fanout with an ordinary queue: PASS, load proven

Ring `[0x040 x4]`, head 0, overflow 0, minerals 2800 -- identical across the trip. Note the
building is at the SAME ADDRESS before and after (`unit=0x00623E58`): the engine restores
into its static 1700-slot table in place, which is what makes the next item possible.

## THE FINDING (arm 5/6): the plugin's over-cap queue SURVIVES A LOAD AND FOLLOWS YOU INTO ANOTHER GAME

Load the save the NO-PLUGIN arm wrote -- a game whose file contains a queue of four and no
overflow whatsoever -- into a fanout process that had earlier queued 8 at the same building
in a DIFFERENT game:

    ok   A1/A2/A3: the ENGINE's ring is exactly right    engine=[0x040,0x040,0x040,0x040,0x0E4] head=0
    PRODQSEL [arm5-load-45] unit=0x00623E58 ... overflow=3 logical=7 minerals=2800

The engine restored its own array perfectly. **The plugin walked into the loaded game still
holding three Probes from the other one**, bound to `0x00623E58` -- the address the restored
Nexus now occupies. `RecordStillLive` cannot reject it: uniqueness, player and hp are all
restored verbatim by the save, so a stale record looks alive.

Consequences, from the code path (`sc_prodqueue.cpp` `PromoteInto`, `Rebalance`):

1. Those three items were PAID FOR IN THE OTHER GAME (minerals 2600 there). The loaded game
   has 2800. So the player is up three Probes they never bought here.
2. The ring is at 4 and the hold is 4, so nothing promotes YET. The moment one Probe
   finishes and a slot frees, the plugin promotes a phantom item into a building that never
   queued it.
3. It is not exotic: queue over the cap, load any earlier save, keep playing.

My arm-6 assertion only compared the ring and PASSED -- the ring is the half that is right.
I have added the assertion that actually catches it (`overflow must be 0 in a game this
process never queued in`) and it is running now.

## Arm 3 (the seam) came back INCONCLUSIVE, correctly

`WINDOW completed units (player 0) 2 -> 3` -- a Probe finished inside the measurement
window, so the ring legitimately moved and the suite refused to call that a save/load
failure. 90 s of build time was not enough for a ~75 s window with the head item already
part-built at save time. Re-running at 240 s now. **The seam WAS reached** (`COVERAGE
overflow held at save time = 3`), so the arm can see the class -- it just needs a clean
window to be readable.

## Engine fact 1, scoped, and it is NOT "type=1"

`Tips_Dlg`'s OK is type=1 too and a posted click has always fired it. The four controls I
have flags for:

| control | dlg | type | flags | posted click |
|---|---|---|---|---|
| `o.O.K` | Tips_Dlg | 1 | 0x20081A58 | WORKS (every run) |
| `l.L.oad` | LoadGame | 1 | 0x20081A18 | WORKS (measured tonight) |
| `o.O.K` | OkCancel | 1 | 0x20001A98 | WORKS |
| `s.S.ave` | SaveGame | 1 | 0x20080A18 | DOES NOT |

The one that fails is the only one **missing bit 0x1000**. So the candidate rule is "a
posted click does not fire a control with 0x1000 clear", NOT "type=1" and NOT "default
button". I would not put that in AGENTS.md as a law on one negative case -- what I can
write at full strength is the HARNESS rule: drive an engine dialog button with a click AND
a Return fallback, and print which one worked, because one of them silently does nothing.
Proposed wording in the PR; if you want the flag semantics nailed down, that is a probe of
its own and I would cut it as a separate task rather than spend an arm on it.
