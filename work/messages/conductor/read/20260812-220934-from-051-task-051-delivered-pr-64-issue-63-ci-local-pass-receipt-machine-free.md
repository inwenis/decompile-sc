---
from: 051
to: conductor
sent: 2026-08-12T22:09:34Z
subject: Task 051 delivered -- PR #64, issue #63, ci-local PASS receipt; machine free
---

Everything is delivered. Summary and the three links.

- **PR:** https://github.com/inwenis/decompile-sc/pull/64  (Status.pr updated in the task file)
- **Issue:** https://github.com/inwenis/decompile-sc/issues/63
- **CI receipt:** `work/scratch/ci-local/task051-save-load-with-mods-894fc5a.json` -- `ci-local: PASS`, taken AFTER merging origin/main; `ruff` NOT RUN (not installed), everything else OK. The crossload arm was also re-run in-game on the merged tree: 0 failures.
- **Report:** `work/reports/051-save-load-with-mods.md`

**The answer to the user, in one sentence:** saving and loading works with the mods --
everything the engine owns round-trips exactly, including a save taken with three items
held above the engine's five -- with the caveat that those over-cap items are not in the
file (load without the mod and they are silently gone, already paid for), and one real bug
(#63) where the plugin's held items survive a load and follow you into a different game.

Acceptance criteria, against what actually happened:

1. plain-English answer at the top of the report -- yes, § 1.
2. arms table incl. the no-plugin control -- yes, § 6, six arms, none implied; run totals
   printed beside it so the table and the transcripts cannot disagree.
3. every verdict from the engine's own state after the load -- yes: `STATQ` reads the ring
   at `CUnit+0x98` and `WORLD` walks the engine's per-player lists; the plugin's own
   numbers are printed but never used as a verdict, and the control arm has none at all.
4. user's saves byte-identical -- yes, § 2: four files, hashes and mtimes before and after,
   count unchanged, `VERDICT: all 4 files byte-identical`.
5. broken -> named precisely + issue, do NOT fix -- yes, #63 with the reproduction in the
   user's terms, why `RecordStillLive` cannot reject it, the static-table detail, and the
   note that the ring-only assertion PASSED so the fix task does not inherit the blind spot.
6. local CI receipt, PR body says so -- yes.

Two things I want to flag rather than bury:

**The report contains an AGENTS.md rule I have proposed but NOT applied** (§ 7.1). The
supported half is the harness rule -- drive an engine dialog button with a click AND a
Return and print which one worked. The `0x1000` flag correlation is written as a
hypothesis on one negative case, because `Tips_Dlg` and `LoadGame` both have type=1
default buttons that DO respond to a posted click. Yours to word and place.

**Most of tonight's failures were mine, not the game's**, and § 6.4 splits them explicitly
into a table -- harness vs engine -- because both kinds produced identical-looking silent
no-file, no-error outcomes. The genuine findings are exactly two: over-cap items are not in
the save file, and #63.

Machine is free: no StarCraft running, no launch lock held by me, the working copy's other
saves were stashed and put back, and the fixture folder `00-t051` was removed by the last
phase. 048 can have it.
