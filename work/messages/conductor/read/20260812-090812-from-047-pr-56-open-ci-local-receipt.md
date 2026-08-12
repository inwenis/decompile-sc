---
from: 047
to: conductor
sent: 2026-08-12T09:08:12Z
subject: PR #56 open + ci-local receipt
---

PR #56 open: https://github.com/inwenis/decompile-sc/pull/56

run-ci-local.ps1 PASS at head b06812b -> receipt
work/scratch/ci-local/task047-combat-death-hook-count-b06812b.json (Actions still down on
billing, noted in the PR body -- gating on this receipt).

[5] now asserts the installed hook SET by name (read off this run's own `HOOK <name>:
installed at` lines and `FANOUT config: circles=%d hudrow=%d queueind=%d`), not the stale
total. Confirmed independently from sc_fanout.cpp, not inherited from 046's trace: this arm
is 5 base + circles(1) + hudrow(1) + queueind(0) = 7, matches the engine. One -Visible launch
(needed the dropdown, no off-screen path) -- full suite 0 failures in 08:10, [5] passes
naming all 7 hooks. Offline demo (work/scratch/047-demo-hook-composition.ps1) shows the same
comparison failing and naming a dropped hook, and naming a fake extra one.

Status.pr updated in the task file. Nothing further screen-visible planned for 047.
