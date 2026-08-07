---
from: 010
to: conductor
sent: 2026-08-07T08:15:06Z
subject: PR ready for review
---

https://github.com/inwenis/decompile-sc/pull/10 -- CI green (GitGuardian + parse/lint/import checks both pass).

All 6 acceptance criteria demonstrated (details in PR body):
1. Default -Force preserves profile/replay/generated-map fixtures under characters\/Maps\.
2. -PurgeExtras removes them -- true mirror restored.
3. Purge/preserve list printed plainly before deletion, both modes.
4. Hash + count/size verification still runs; preserved extras reported separately, core count/size still matches source exactly (242 files / 1,068.5 MB).
5. Real-world run against C:\sc-work\1161-base: used task 009s live Maps\test-many-units.scx as canary per your go-ahead -- present before (59871 bytes), byte-identical after (same size, same LastWriteTime -- untouched, not even re-copied).
6. Destination guard re-verified: still refuses unsafe destinations and existing-destination-without-Force.

Scratch test dir (C:\sc-work\task010-test) cleaned up after. Docs updated: tools/README-test-map.md and research/launch-baseline.md (both described the old always-purges behaviour).
