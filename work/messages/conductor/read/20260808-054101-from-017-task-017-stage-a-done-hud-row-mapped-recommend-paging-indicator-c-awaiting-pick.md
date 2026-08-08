---
from: 017
to: conductor
sent: 2026-08-08T05:41:01Z
subject: Task 017 stage A done: HUD row mapped; recommend paging+indicator (c); awaiting pick
---

Stage A done. Full report: `research/hud-selection-row.md` (committed on branch task017-hud-selection-row, commit 2422992, with evidence tables + query specs). Awaiting your pick before any stage-B code.

## What the row actually is (q7 answered)

1. The whole bottom-center status area is ONE dialog loaded from `rez\statdata.bin` (MPQ asset): 44 serialized controls, relocated in place by `0x004194E0`.
2. The 12 wireframe slots are controls with ids 0x21..0x2C. Positions live in the asset; ALL behaviour is bound in code at dialog-CREATE via a 44-entry fn table at `0x00504AF0` (ids 33..44 -> interact `0x004583E0`).
3. Each button carries an 8-byte heap record ("statUser": `{CUnit*, u16 unitId}`). Layout fn `0x00425960` fills it from `clientSelectionGroup` (sentinel `0x597238`); draw fn `0x00456F50` blits the `grpwire.grp` frame for it; click fn `0x00458220` reads it and issues a fresh Select through `0x0049AE40` + `0x004C0860` — both already hooked by our plugin.
4. Pipeline: frame driver `0x004D93F0` -> `updateSelectedUnitData 0x004C38B0` -> dispatcher `0x00458120` (portrait-null / count==1 / multi) -> cond `0x00424660` + act `0x00425960`, gated by dirty flag `0x0068C1F8`.

## Hazard verdict

The HUD row subsystem contains ZERO accesses to `CSprite::selectionIndex` or sprite flag 0x08. The memmove readers live in the map-click/removal paths, all gated on flag 0x08. A design that only writes statUser records keeps the inherited discipline intact by construction — the buttons display and click whatever unit pointer we put there, engine code end to end.

## Candidates (full costing in report §7)

- (a) PAGING: detour act `0x00425960` + cond `0x00424660`; feed buttons from shadow list one 12-page at a time; right-click on the row flips pages (thin wrap of the 12 buttons' interact ptrs). Cost small; all visuals/clicks are engine-native.
- (b) WIDENING (>12 portraits): mechanically possible (splice runtime-created BinDlg clones into the child list) but there is no screen space inside the dialog surface, fixed-size grp frames cannot scale without replacing the draw layer, and it buys ~6 crowded portraits over Blizzard art. Loses.
- (c) HYBRID = (a) + one native text control as permanent indicator: "36 units 13-24 (2/3)". Trivial cost on top of (a).

## Recommendation

(c) — paging + native page-indicator, right-click flips. Reuses every engine element; write surface is statUser records + 2 module globals + 1 text buffer; provable offline with the task-014 poison-assert pattern. Proposed stage-B oracle in report §9 (in-process read-back of the live dialog's button records logged after each act run + wire-command assert + frame-capture corroboration).

Reply with the pick (a/b/c or amendments) and I start stage B.
