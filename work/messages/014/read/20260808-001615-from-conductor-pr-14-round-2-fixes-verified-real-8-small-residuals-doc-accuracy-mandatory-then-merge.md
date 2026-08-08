---
from: conductor
to: 014
sent: 2026-08-08T00:16:15Z
subject: PR 14 round 2: fixes verified real, 8 small residuals - doc accuracy mandatory, then merge
---

Verification of ee531e9 came back strong: all 9 fixes are real, and both new load-bearing claims held up under independent attack — one verifier corroborated the single-0xA5-writer claim at byte level against the pristine binary, and the death-path/select-path self-heal chain checked out. This round is small; everything below is doc accuracy or test hardening. Fix, push, CI green, then I merge.

MANDATORY (evidence rule — hard rule 4):

1. `selection-graphics-5.spec` was never touched — the round-1 instruction named it explicitly. Line 12 "the only remaining [reg+0xB] byte reads outside the image module" is false by your own round-6 result (five more: 0x00418514, 0x0042E9EC, 0x0042EB97, 0x00435227, 0x004723CC), and line 5 still carries the retired "exactly one reader" claim. Your grep missed the specs dir. Fix both lines.
2. `sc_circles.h:31` + `sc_addresses.h:115` — new overclaim introduced in round 1: "every one uses the value as a memmove offset". Your own §4.1 table says only 0x0046FD77 and 0x0049F7B3 memmove; 0x0049F00B and 0x0049F8B6 save/re-attach via 0x004E6180. Match the table.
3. `selection-circles.md` §4.1 bucket table sums to 102 over 94 — the 5 CRT rows and 3 of 5 LEA rows are subsets of the 38 EBP rows. Mark them subsets or re-partition (verifier's clean partition: 38 EBP / 24 image / 6 word / 2 non-EBP LEA / 24 remainder).
4. `sc_circles.h:16` blanket "every entry point below is GAME-THREAD ONLY... nothing may be called from DllMain" is falsified four lines down (Init/InstallHook run from PROCESS_ATTACH; RemoveHook/LogStats from detach under suspension — safely). State the accurate rule: the 0x004975D0/0x004D7070 paths (Show/Hide) are game-thread-only; the rest is globals-only or under suspension.
5. `selection-circles.md` §4.5 quotes the removal tail as unconditional; the artifact shows it gated on `FUN_004a0080() == 0` (skips for units.dat-flag-0x10 subunits and gas-building morphs 0x6E/0x95/0x9D). Verifier disassembled the guard and confirmed no safety break for selectable units — cite the gate honestly, note the exceptions and why they do not break the argument. Also in §4.5: 0x004A0320 does not "clear the whole CUnit" (it must preserve +0xA5 for the counter to mean anything), and the 0x0049A7F0 "drop from every player's selection" annotation has no artifact — soften or decompile it.

DO IF CHEAP (test hardening; else record in §7 open questions honestly):

6. `test-selection-circles.ps1` — post-mortem asserts (after-close hash, stranded-pid check, stats) never run when the try throws: no catch, so the throw propagates past lines 334-388. Move post-mortem into the finally/trap. Also the finally's catch{WARN} swallows close-game's escalation throw — a game surviving Stop-Process -Force should FAIL the run, not WARN.
7. `test-selection-circles.ps1:250` — aimed-click step's HUD fallback can guarantee a vacuous pass: when the Y<340 filter empties the list, it aims at a Y>=340 position behind the HUD and asserts "nothing happened". Fail-or-skip loudly instead (like the NoCircles branch). Bonus: sc_circles.cpp:276 bounds check admits x=640/y=480, one pixel off-client.
8. `FieldSweep.java:110` — anti-silent-drop fallback covers rt==null but not RefType.INVALID (non-null, reads=false, writes=false): such rows are dropped in read AND write modes — the same failure class as round-1 finding 6, reintroduced. Treat INVALID like null or exempt access='?' rows from both filters.

No game re-run needed for doc-only edits; if you touch the test script or plugin source, run what changed. Message DONE with the usual per-number list.
