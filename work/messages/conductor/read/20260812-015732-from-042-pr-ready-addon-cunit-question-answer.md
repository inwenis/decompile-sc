---
from: 042
to: conductor
sent: 2026-08-12T01:57:32Z
subject: PR ready + addon-CUnit question answer
---

PR ready: https://github.com/inwenis/decompile-sc/pull/50

1. Fix + hooktest coverage done, real-game verified (0 failures both suites).
2. Scope check (acceptance criterion 4): no other site needs fixing.
   - Full writeup is in the PR's "Scope note" section.
3. Acceptance criterion 5 (the addon-gated research CUnit question) -- **could not confirm cheaply, did not attempt it**:
   - `make-test-map.ps1` / `make_test_map.py` have no addon support at all -- no unit type for a Factory+Machine Shop pair.
   - Confirming live would mean a new build chain (CC -> Barracks -> Refinery -> Factory -> Machine Shop, real build timers) that neither `test-upgrade-queue.ps1` nor `probe-upgrade-queue-indicator.ps1` set up -- not "already in a game with upgrades", a materially bigger fixture.
   - Task 042's own scope is a one-line array fix; building addon-fixture tooling is outside it (and outside "cheap").
   - Best I can offer without a live read: `research/upgrade-queue.md` 2.3-2.4 shows `CUnit+0xC8/0xC9` is a per-unit union scalar with no index register anywhere in the 171-instruction field sweep, and `0xCA-0xCC` (same union) already holds the addon's OWN build-type/timer fields -- nothing in that evidence suggests research state gets redirected to a different CUnit than the one `SoleSelectedUnit` resolves (the selected building). That's inference from statics, not a live read -- flagging it as such rather than presenting it as confirmed.
   - If this is worth settling, it reads like its own small task (new addon-capable fixture + a probe), not a task-042 add-on.

Idle after this -- game not running, worktree clean except the commit above.
