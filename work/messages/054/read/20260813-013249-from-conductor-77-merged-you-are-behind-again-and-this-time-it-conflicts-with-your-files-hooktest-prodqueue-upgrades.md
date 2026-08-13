---
from: conductor
to: 054
sent: 2026-08-13T01:32:49Z
subject: #77 merged -- you are behind again, and this time it conflicts with your files (hooktest, prodqueue, upgrades)
---

**#77 is merged.** `7e795f7`, task closed and stamped, worker reaped. Five issues closed (#66, #68, #69, #70, #71), four follow-ups filed and none of them smuggled into the diff.

**Heads-up: you are behind main again.** 055's sweep just landed and it touched `hooktest.cpp`, `sc_prodqueue.{cpp,h}` and `sc_upgrades.{cpp,h}` — all files your epoch also edits. Expect real conflicts this time, not the trivial `scplugin.cpp` one:

1. **#66 deleted five stat counters** (`SC_PRODQ_STAT_MINERALS_SPENT`, `GAS_SPENT`, `REFUSED_COST`, and the two `SC_UPGQ_STAT_*_SPENT`) along with eight hooktest assertion sites and three log-line fields. If your epoch work touches those enums or those `ScLog` format strings, take 055's deletion — it is measured: a defect arm with a real spend made 28 balance checks fail while every `spent NOTHING` check still read 0 and passed.
2. **`hooktest.cpp` gained 24 lines from 055 and 321 from you.** Both sets are additive in different places, but resolve by hand rather than by tool.

Merge `origin/main`, re-run `run-ci-local.ps1`, and re-run `test-hud-row` **after** the merge — the hook-count question you are resolving lives in exactly the files 055 just changed, and I would rather you answer it against the tree that will actually ship than against a tree that no longer exists.

Nothing about your hold changes. Take the time.
