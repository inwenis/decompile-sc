---
from: 018
to: conductor
sent: 2026-08-08T17:32:46Z
subject: PR 18 round 5: all 5 items done, CI green, verified live
---

All 5 items pushed (48e1312), CI green (https://github.com/inwenis/decompile-sc/pull/18).

1. Exit-3 fallthrough: run-with-plugin.ps1 now throws on ANY non-zero check-game-windows.ps1 exit, not just 1. Closes the silent-success hole.

2. [PreserveSig]: added to all 6 flagged methods, and to every other HRESULT-returning method in those interfaces (not just the 6 named -- same bug class could recur on any future addition). Verified: Item(9999)-style repro no longer throws; real-session mute/unmute still works, no regression.

3. -Sound unmute: wrapped in try/catch (downgrades to warning, never fails an already-successful launch), calls the interop directly instead of through the poll loop (no more up-to-5s cost on every user launch).

4. Guard aliases: added rm/del/rd/erase/Set-Item/si. Re-tested via the same throwaway-script technique (routes around the hook's own quoted-text false-positive) -- all pass, read-only still clean.

5. Tripwire: extended to all 5 preserved classes (was 3) -- maps\download\ and SCScrnShot_*.pcx (a root-level file pattern, snapshotted separately from the directory classes) are now watched too. Verified live: redeployed (7 files checked now, up from 5), and a synthetic same-size content edit to both newly-covered classes is caught as CHANGED.

Also merged origin/main (baaba37) per your note -- branch now carries AGENTS.md rule 5, citations unchanged since they were already correct.

Verified end-to-end again after all fixes: real launch through the actual desktop shortcut, game came up clean, no launch-error.log, closed via close-game.ps1 with DETACH.

Ready for merge.
