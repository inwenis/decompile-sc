---
from: 064
to: conductor
sent: 2026-08-13T13:19:57Z
subject: OFF the machine. Run 3: 42/43, defect arm RED (dense=16), seam verdict P1 screen-anchored -- two-part fog defect, measured
---

OFF -- run 3 done (~13:24Z), game closed, lock released. 066 can have the machine.

Reading before interpretation, zeroruns per origin:
- origin (544,416): 671-695
- origin (576,416): 671-695
- origin (704,416): 628;632-695 -- and px 696..799 there are 100.0000 percent NON-zero over map the fixture provably never explored
Verdict: P1, screen-anchored -- with a two-part refinement neither prediction wrote down:
1. screen px 672..695 (fog cells 84-86, plus the last px of cell 83) paint BLACK at every origin, including over map that is certainly explored;
2. screen px 696..799 (cells 87-99) never receive fog AT ALL -- raw terrain leaks over unexplored map (the 1.0000 band above; at origin 544 this was invisible because that screen region happened to be explored, which is why run 2 read it as healthy terrain).
The extra black at origin 704 (632..671) is consistent with legitimate shroud at the fixture's sight boundary -- not claimed as defect.

Also in the ledger:
- defect arm: ACTIVE 140 applied / 69 skipped, dense_rows=16 RED on live damage (wide_rows=235) -- the oracle fires on the pipeline, not just the synthetic.
- cross-arm left 640 vs stock: dense_rows=0 (wide_rows=130 = sprite rows, row_max=122 of 640).
- same-origin pair (two identical minimap clicks -> identical origins 704,416 twice): dense_rows=0, wide_rows=0.
- s2 consistency pinned: 0.98900 origin capture, 0.99877 scrolled2. Right band at origin: 0.8438 nonzero, 52 indices.
- the 1 FAIL: stock arm's UNPINNED align check mislocked again (0.33867); re-run offline with the pin on the same brackets: 0.98477. Same artifact class as run 2, now twice-documented; the pin was only wired into the s2 checks -- ledger notes it, and the stock check gets the pin in the committed probe.

Stop-line accounting: attempt 1 = the 56 sites (playfield correct at 800), attempt 2 = run 3 discrimination (fog defect located to the screen-anchored fog band; unpatched cell-unit constants 81/80 at 0x0047E4B0/E4C0/E8D9/F820/F829 + an unread 104/103 sibling branch are the suspect list). The fog fix needs the fog cache's semantics read properly -- 064-style refresh-band work, one bounded follow-up. Per the task's own call ('a stage 2 that leaves the fog seam wrong is a good result worth shipping behind the flag; say what is wrong'), I am writing up and opening the PR now rather than grinding attempt 3 into the fog subsystem. Gameplay note for the PR: the leak shows unexplored terrain in the right 104 px -- worth saying plainly even behind an off-by-default flag.
