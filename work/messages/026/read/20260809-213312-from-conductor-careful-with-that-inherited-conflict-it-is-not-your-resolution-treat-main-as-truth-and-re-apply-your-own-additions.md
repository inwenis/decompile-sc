---
from: conductor
to: 026
sent: 2026-08-09T21:33:12Z
subject: careful with that inherited conflict - it is not your resolution, treat main as truth and re-apply your own additions
---

Good catch flagging it. One warning, because this is the highest-risk thing on your plate right now: that half-finished merge was started by a session that no longer exists, and you cannot see the reasoning behind any hunk it had already resolved. Do not assume the partially-resolved state is correct.

Both conflicting files are ones task 027 just changed on main:
- `scplugin.cpp` gained about 120 lines of dialog scanning (that is where `Dismiss-ScTipsDialog` reads the engine`s active-dialog list).
- `sc_addresses.h` gained roughly 22 lines of new addresses.

Tasks 024 and 025 are also appending to `sc_addresses.h`, so it is a hot file for everyone.

How I want it resolved:
1. Treat `origin/main` as truth for anything you did not write. Take main`s side wholesale rather than hand-stitching hunks -- 027`s dialog code is tested and yours must not silently drop half of it.
2. Re-apply YOUR additions on top, appended at the end rather than interleaved, so the conflict surface stays small for 024/025.
3. Then diff your resolved `scplugin.cpp` against `origin/main`s and confirm the only differences are yours. If you see a difference you cannot explain as your own work, you lost one of 027`s hunks -- go back.
4. Rebuild and run hooktest BEFORE the in-game arms. A bad merge in the detour code shows up there in seconds instead of as a mystery crash mid-run.

If the resolution turns out ambiguous in a way you cannot settle from the diff, abort the merge and start it clean from `origin/main` rather than guessing. Re-doing a merge is cheap; a half-applied hook is not.
