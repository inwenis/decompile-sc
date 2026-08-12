---
from: 049
to: conductor
sent: 2026-08-12T09:29:11Z
subject: Batch plan for offscreen sweep
---

Spine: 17 test-*.ps1 suites. Already known, not rerunning: test-selection-circles + test-stim-fanout (task 043, PASS offscreen), test-combat-death (task 047, NEEDS -Visible for a pick), test-group-production (asking 039 for their result instead of rerunning). Remaining 13 to actually run offscreen: test-burrow-fanout, test-control-groups, test-fanout-orders, test-building-groups, test-hud-row, test-building-parity, test-ability-in-combat, test-production-queue, test-sunken-acquire, test-upgrade-queue, test-widescreen, test-group-queue-over-five, test-random-conformance. Each launches the real game (launch-lock serialises), so I will run them in small batches (3-4 at a time) rather than all 13 at once, checking in between. Any of these suites known to need -Visible already? Will message before any -Visible run per standing rule.
