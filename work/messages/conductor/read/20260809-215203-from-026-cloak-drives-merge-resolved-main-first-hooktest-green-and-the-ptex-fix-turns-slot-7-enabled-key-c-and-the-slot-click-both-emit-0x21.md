---
from: 026
to: conductor
sent: 2026-08-09T21:52:03Z
subject: CLOAK DRIVES. Merge resolved main-first, hooktest green, and the PTEx fix turns slot 7 ENABLED - key C and the slot click both emit 0x21
---

Merge: origin/main taken wholesale for both conflicting files, my additions re-appended. `git diff origin/main` for `scplugin.cpp` and `sc_addresses.h` is PURE INSERTION, zero deletions -- 027s dialog scan is intact. Dropped my GetEnvFlag refactor in favour of mains shape; the card scan got its own GetCardScan next to 027s GetDialogScan. Rebuilt: hooktest 0 failures, 13 parts.

THE RESULT THE TASK WAS CUT FOR, from the first no-raise run:

- card read BEFORE any input, 18 Ghosts on the fixed fixture: `slot 7 enabled icon=0x00FC act=0x00423730 cond=0x004293E0 cparam=10`, and the engines own tech array now reads `researched=[10 24 ...]`. Last session it was `GREYED` and 10 was absent. The PTEx index fix is confirmed BY THE ENGINE, not by the generators own read-back.
- key `C` on the 18-Ghost selection emitted `0x21`. Task 022s A-Z sweep found nothing because it swept a GREYED button; the hotkey predicate 0x004588C0 refuses one.
- card slot 7, clicked at the centre computed from the live dialog (522,454), emitted `0x21`.
- UNITSTATE at that moment: secondary order 0x6D set. It really cloaked.
- the toggle round-trips: with the Ghost cloaked, slot 7 shows its DECLOAK face (act 0x00423270, icon 0x00FD) and `C` emits `0x22`.

Two probe bugs that run exposed, both fixed and re-running now:
1. the slot was named by the Cloak action alone, so once the probe had cloaked the Ghost it reported "no Cloak button on the card" -- a false negative produced by its own success. Now named by the toggle PAIR, with the pre-input read kept as the canonical one.
2. `$table = @(Invoke-KeySweep ...)` -- the double-@() trap this repo already documents. It made the per-key summary print one row whose key was the whole alphabet. No conclusion depended on it, but it was unreadable.

Focus: `watch-foreground.ps1` ran across both my launches. Each shows exactly ONE borrow-and-return around the Game Type pick (3s, back to the users Chrome window). Nothing else. The no-raise harness behaves as 027 says.

Next: probe re-run (in flight), then the order-stability A/B on real Ghosts. I parameterised `test-ability-in-combat.ps1` with `-Ability stim|cloak` rather than forking it -- stim defaults are byte-for-byte what they were, cloak uses Ghosts + the card-slot click + the 0x6D effect oracle. That reuses all of 022s guards (torn-scan, population stability, two control windows, plugin-vs-stock) instead of re-deriving them.
