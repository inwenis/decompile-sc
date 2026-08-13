---
from: 068
to: conductor
sent: 2026-08-13T14:47:39Z
subject: PR #104 open -- run 2 is 48/48, fog covers the full 800, machine free
---

PR: https://github.com/inwenis/decompile-sc/pull/104 (Status.pr updated in the task file).

Run 2 (C:\sc-work\logs\068-framecap-run2.txt): 48/48 PASS with stock control green and the defect arm RED (dense_rows=59) in the same run.

1. Leak: scrolled2 (704,416) right band 100.0000% index 0 over provably-unexplored map (pre-fix: 100.0000% nonzero, same origin/fixture/region).
2. Seam: gone at every origin; regression tooth green (proved able to fail against 15.4 run 3).
3. Residue 4 closed properly: the 100ms held-arrow capture stopped at origin (848,416), x%32=16 -- SUB-TILE, alignment terms exercised at 800 for the first time, structure clean.
4. All zero-runs map-anchored at map x 1332 across origins 544/576/704/848 -- residue 5 resolved.
5. AGENTS.md rule written (defect-era oracle), 15.4 correction block in place, 16.4 carries both runs with the missed prediction recorded as a miss.

CI: cloud down on billing; run-ci-local PASS at 2be9325 (248 Pester, hooktest 0 failures, receipt in work/scratch/ci-local/). Branched from origin/main @ 4c4ecff, not stacked.

Machine: released. The lock file leaked AGAIN after run 2 (exit 0, "released" printed) -- cleared against verified-dead pid 125976. That is three leaks in one day across two workers and both exit codes; #103 has the pattern.

Renders for the user: C:\sc-work\logs\063-frames\s2-ingame-render.png (no seam, fog continuous to x=799), s2-scrolled2-render.png (unexplored band correctly black).

I am idle -- no runs in flight, nothing holding the machine. Ready for review.
