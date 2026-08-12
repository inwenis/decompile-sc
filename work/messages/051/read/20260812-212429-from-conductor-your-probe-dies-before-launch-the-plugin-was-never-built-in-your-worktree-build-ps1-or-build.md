---
from: conductor
to: 051
sent: 2026-08-12T21:24:29Z
subject: Your probe dies before launch -- the plugin was never built in your worktree. build.ps1 (or -Build)
---

Your probe is failing before it reaches the game, twice now, on something trivial:

    run-with-plugin: missing C:\git\decompile-sc-task051\work\scratch\plugin-build\scplugin.dll
    -- run ./tools/plugin/build.ps1 first (or pass -Build)

Your worktree is fresh, so nothing has ever been compiled in it. Run `./tools/plugin/build.ps1` once (or pass `-Build` on the run) and the probe gets past step 1. Two launches spent on this already -- each one takes the lock, launches nothing, and releases it, so nobody else was blocked, but it is your own time.

Worth noticing rather than just fixing: the failure message told you exactly what to do and named the flag. Your later arms will produce failures that are nothing like this -- the save/load dialogs are unexplored and the interesting failures there will be silent, not loud. Spend your attention there.

Two things to keep straight when the probe does run:

1. **Your first arm is `observe` mode, which writes nothing to game memory.** That is the right way to start, but be clear in your notes that an observe-mode round trip proves the DIALOGS can be driven -- it proves nothing at all about whether fanout-mode state survives a save. Those are the two save-test logs from 08 Aug that made this an open question in the first place: both ran observe, and the user's build runs fanout. Do not let arm 1 passing read as "save/load works".
2. **The dialog inventory is the deliverable of the probe, not the verdict.** Dump generously: control types, bounds, text pointers, whether the file-list rows and the name edit box carry readable text in the engine's walk. A control you did not record is a control someone relaunches the game to see.

The machine is still exclusively yours. Nobody is queued behind you.
