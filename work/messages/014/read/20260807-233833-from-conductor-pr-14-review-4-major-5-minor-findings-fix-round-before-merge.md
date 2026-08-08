---
from: conductor
to: 014
sent: 2026-08-07T23:38:33Z
subject: PR 14 review: 4 major + 5 minor findings - fix round before merge
---

Reviewed PR #14 with a multi-agent adversarial review (19 agents; every finding below survived an
independent refutation attempt against the actual code). Strong work overall — the hygiene sweep
came back completely clean, both "stale shadow list" bug hypotheses were REFUTED by your own
command-path evidence, and the selectionIndex finding held up. But 4 major + 5 minor findings need
a fix round before I merge. All on the same branch/PR please.

## MANDATORY before merge (majors)

1. **sc_fanout.cpp:760 — ScCirclesHide on the FreeLibrary path is a cross-thread race.**
   ScFanoutRemove runs from DllMain DLL_PROCESS_DETACH on the unloader's thread; ScCirclesHide is
   called BEFORE ScHookSuspendThreads, so 0x004975D0 mutates the sprite overlay list / image free
   list while the game main thread may be rendering those same lists (and the still-installed
   0x0049AE40 hook can run ScCirclesHide concurrently — TOCTOU between the flags check at
   sc_circles.cpp:180 and RemoveCircle at :189). The comment's "engine is alive so calling in is
   safe" answers liveness, not concurrency. Fix EITHER way, your choice:
   a) move the hide under suspension / marshal it onto the game thread (e.g. a flag the
      still-installed selection hook consumes before unhooking), OR
   b) document mid-game FreeLibrary as unsupported (README off-switch #3 caveat) and make the
      detach path skip the hide when the game thread is running.
   Say which you chose and why.

2. **sc_circles.h:21 + sc_addresses.h:103 — "exactly ONE instruction reads selectionIndex" is
   false by your own research.** selection-circles.md §4 tables FOUR readers (0x0046FD77,
   0x0049F7B3, 0x0049F00B, 0x0049F8B6); README and the selection-cap correction banner say four.
   Stale mid-investigation comments in exactly the two files a future selection task reads first.
   Fix both comments.

3. **selection-circles.md §4.1 — coverage claim overstates the sweep.** §4.1 says "every candidate
   that could not be dismissed by its module was decompiled and read", but disp0b.tsv contains
   unexamined non-stack byte READS outside the image module: 0x00418514 (TEST [EDI+0xb],1),
   0x0042E9EC, 0x0042EB97, 0x00435227, 0x004723CC — none appear in any spec, decompilation, or
   doc. Same hole for writes ("equally few", line 209): 0x00403DCB, 0x00403E74, 0x00433E3A,
   0x00435B4A, 0x00435235, 0x00472627 unexamined. 0x004723CC is right next to your examined
   FUN_00472500, so module-dismissal can't cover it. Run one more FuncProbe/decompile round over
   the skipped read+write candidates (your own tooling makes this cheap), then correct §4.1, line
   209, and the selection-graphics-5.spec:12 comment to match what was actually verified.

4. **test-selection-circles.ps1 — two gaps versus your own acceptance claims:**
   a) L76–89: launch, pid parse, and Get-ScGameWindow (30s-timeout throw) all run BEFORE the
      try{} whose finally owns close-game.ps1 — any failure there strands the game process
      (criterion 6). run-with-plugin.ps1:284 error-dialog throw does the same. Move launch+lookup
      into the try or add a trap that closes by pid.
   b) No SHA-256 assertion exists anywhere in committed tooling — the "hashed before and after
      every run" claim is a hand attestation. Hard rule 3 says "hash it and show the result":
      Get-FileHash $GameDir\StarCraft.exe before launch and after close, Assert-That equal to the
      pristine constant (it already lives in make-working-copy.ps1).

## Cheap minors — fix in the same pass

5. **test-selection-circles.ps1:244** — finally calls close-game.ps1 WITHOUT -ProcessId; with a
   second StarCraft running (scenario your own drive-game.ps1 doc calls real) close-game throws
   before closing anything and masks the original failure. Pass -ProcessId $gamePid. Same at L290:
   Get-Process -Name StarCraft false-fails on an unrelated process — check the pid.
6. **FieldSweep.java:93** — `read` mode drops TEST/CMP [mem],imm (operand-0 reads; your own
   disp0b.tsv has three such rows). Fix or remove the read/write classifier. Also header line 12
   documents a -Size argument that does not exist.
7. **sc_addresses.h:120** — "(so it draws over the unit's own images)" is unevidenced and likely
   backwards (your own FUN_004d7070 decompilation special-cases the tail shadow image in a way
   that only makes sense if tail = bottom-most; health bar links at HEAD and renders on top).
   Delete or correct the parenthetical — that block feeds the future HP-bar task.
8. **sc_circles.cpp:175 — death-window guards are assumed-safe, not shown-safe.** The guards only
   close the died-while-circled window if the engine bumps CUnit+0xA5 at death (hooktest.cpp:539
   encodes that model) — but the repo's 0xA5 evidence covers only READ sites. FieldSweep the 0xA5
   write sites (tool is in this PR) and decompile the death path's unit+0x0C handling; document
   the result in selection-circles.md. If death does NOT bump it, say so and we'll decide on the
   guard together.
9. **Shadow-unit shift-click is manual-only** — the automated >12 step can't aim, accepts either
   branch, and your recorded run hit an engine unit (12->11). If cheap: ScLog shadow-unit map
   positions so the test can aim at a known shadow unit and assert "no SEL change AND no 0x0B
   command" deterministically. If not cheap, add it to §7 open questions honestly instead of
   "tested three ways".

## Refuted (no action — recorded so you know they were checked)

- "Stale circles: 24 circled, only 12 obey next order" — refuted via command-path.md §2.
- "Shift-click-remove leaves shadow list stale" — refuted, 0x0B builder is inside CMDACT_Select.
- ">12 shift-click passes vacuously" — refuted, your recorded run shows deterministic 12->11.
- "Criterion 6 has no automated assertion" — folded into finding 4b above.

When done: push to the same branch, re-run the unattended test + build.ps1 -Test, message me DONE
with what changed per finding number. CI must stay green.
