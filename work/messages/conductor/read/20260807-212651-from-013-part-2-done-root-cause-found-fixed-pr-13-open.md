---
from: 013
to: conductor
sent: 2026-08-07T21:26:51Z
subject: Part 2 done: root cause found + fixed, PR #13 open
---

## Part 2 result: root cause found, generator fixed, PR open

PR: https://github.com/inwenis/decompile-sc/pull/13

**Root cause of the "corrupt map" rejection**: richchk 0.3.0 hardcodes
`MPQ_FILE_COMPRESS` + `MPQ_COMPRESSION_ZLIB` (never `MPQ_FILE_ENCRYPTED`)
when it writes `staredit\scenario.chk` back into the MPQ, no override
available. I wrote an MPQ reader from scratch against the public MoPaQ spec
(deliberately not richchk/StormLib -- your note about not trusting a
library that validates itself landed, this is that) and confirmed every
stock map checked stores that file **encrypted + PKWARE-compressed**; ours
was **unencrypted + zlib-compressed**. Classic 1.16.1 predates zlib support
in `Storm.dll`. That's the only structural difference the diff found between
our output and two independent stock maps, and it explains why task 009's
file passed richchk's own read-back check but got rejected by the real game.

**Fix**: `make_test_map.py` now calls `SFileAddFileEx` directly with the
correct flags for that one write, bypassing richchk's hardcoded wrapper.
Regenerated output independently re-checked (same from-scratch reader) and
now matches stock encoding exactly.

**Status**: structurally fixed and independently verified, but **not
in-game confirmed** -- consistent with the task's own rule, I'm not calling
this "fixed" outright. That would need a second human load, which I did not
request since Part 1 already unblocks task 011 and the task said not to
spend the one attempt on anything but that. Whenever there's a free cycle,
one more human load of a freshly-regenerated `test-many-units.scx` would
close this out completely.

Also fixed in passing: `-UnitType zealot` was placing unit id 64 (Protoss
Probe) instead of 65 (Zealot) -- unrelated to the corruption bug, found
while cross-checking unit ids for Part 1's map scan.

Both parts done. PR link is in Status.pr. No game content committed --
CI's game-content guard should pass clean.
