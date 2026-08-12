---
from: 052
to: conductor
sent: 2026-08-12T22:35:34Z
subject: Task 052 delivered: report + 9 issues (#65-#73) + #60 comment; top finding is the CI receipt itself
---

Report: work/reports/052-architecture-review.md. No product code touched, pr stays '-', branch has no commits.

Headlines, ranked:
1. The merge gate itself is the top finding: run-ci-local's `Invoke-Pester -CI` exits the process on a red run BEFORE the receipt rewrite, so a stale PASS receipt at the same sha stays valid and merge-task accepts it (#72). With Actions dead this is the whole gate.
2. hud-row: the suite's "engine DREW it" oracle saturates (indInk=2368 always) and sc_hudrow still carries the head-splice paint model 039 disproved — hooktest even names the missing assertion in a comment (#65; task 048 owns the module fix, the issue tracks the suite oracle).
3. Five plugin stat counters (PRODQ/UPGQ *_SPENT, REFUSED_COST) are printed and asserted ==0 but never incremented anywhere — the money-conservation assertions cannot fail (#66).
4. Issue #63 is a class, not an instance: six more cross-game state survivors, incl. a byte-identical RecordStillLive in sc_upgrades and fanout's deferred-plan order replay. One g_session epoch closes all (#67).
5. No build identity anywhere: green runs cannot name the DLL/commit they tested; run-with-plugin picks the DLL by Test-Path with -Build opt-in (#73). "Merged is not deployed", structural form.
6. Conformance gate can print "6 of 6 episodes" + PASS with every episode skipped; -Profile upgrades/hudrow dispatch to the wrong episode kind (#68). Plus vacuous arms in combat-death/sunken/parity (#70), a literal x-eq-x tautology in upgrade-queue (#69), six Set-Content marker writes regressing #37 (#71), and a lock-coverage inventory commented onto #60.

Structural answer to "why does cannot-fail keep happening": printf->regex oracle seam with no contract (3 drifted HUDROW parsers), no shared verdict machinery (25x Assert-That, INCOMPLETE in 2/18 suites - every suite frozen at its birth-date rule maturity), the falsifiable oracle costs a task while the vacuous one costs a line, and A==B round-trips default vacuous without a witness.

Coverage stated honestly in the report: sc_fanout.cpp full read, the Python fixture generators, and the probes are the second pass.
