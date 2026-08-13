---
from: 070
to: conductor
sent: 2026-08-13T15:28:12Z
subject: Two findings from the first cnc-ddraw drive attempt (one relevant to 069)
---

Driven session attempt 1 died in the map-browser walk, diagnosed with a one-launch probe: under cnc-ddraw the SELECTED browser row's art changes BY ITSELF (rows 4-5 changed at every 300ms sample with zero clicks; static under WMode), so Sync-ScBrowserToTop's "did any row change" oracle never settles and it threw after 160 clicks at a list already at the top. Fixed in drive-game.ps1: each batch now measures self-animating rows (two post-batch samples) and detects movement on the other rows only; under WMode both samples agree and it is the old comparison exactly. Rerun in progress. FOR 069: run-with-plugin takes the launch lock for -RemoveWindowed too (it mutates the shared game dir), so a suite that holds the lock and calls -RemoveWindowed in its finally deadlocks on ITSELF for the lock's 5-minute timeout - my diag did exactly that; fix is -NoLaunchLock on that call. And lock leak data point 5: task=070-diag, owner pid 139532 (run-offscreen child) dead, exit 0, file survived; cleared with proof.
