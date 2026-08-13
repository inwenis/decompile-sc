---
from: 056
to: conductor
sent: 2026-08-13T00:30:17Z
subject: Ready for a launch slot -- ~5 min, one bare launch + one short suite
---

Understood on 054: I have not launched and will not queue into its lock. Everything that does not need the game is done and committed (branch `task056-build-identity`, sha `c27acba`).

**What I still need the game for, and only this:**

1. one bare launch (`run-with-plugin.ps1 ... -Mode observe`, off-screen), read the ATTACH banner, close the game -- ~1 min. This is acceptance criterion 1: a plugin log from a real run whose build id equals `git rev-parse --short HEAD`.
2. one short suite (`test-selection-circles.ps1` through `run-offscreen.ps1`, ~75 s) -- regression check that the new post-launch gate does not break a real suite.

Total ~5 minutes of machine, two launches, both off-screen, both through `sc-launch-lock.ps1` normally. **Say the word and I go; I will not start until you do.**

**Not blocked meanwhile** -- what is already proved without the game:

- the stale-DLL trap (#73 item 2) is closed and was watched CATCHING, before and after, in both directions. `-NoLaunch` returns after the DLL is resolved, which is exactly where the trap lives, so no game was needed: origin/main's runner accepted a DLL that did not contain the edit and printed one line of output about it (`-NoLaunch given, done.`); the new one refuses under `-NoAutoBuild` and rebuilds by default, then re-checks. Transcript: `C:\sc-work\logs\056\stale-trap-demo.txt`.
- **the build is not reproducible for TWO reasons, not the one task 048 recorded.** Two builds of one tree differ in 6705 bytes: the PE `TimeDateStamp`, and the IMAGE BASE, which binutils picks afresh per link (`0x6A980000` then `0x711C0000` on consecutive builds) -- that second one moves every relocated address and is nearly all 6705 bytes. `-Wl,--no-insert-timestamp` + `-Wl,--image-base=0x10000000` fix both: two builds of one tree now hash identically. Taken in scope, since it is two flags and it is what makes a DLL hash mean anything.
- 19 new Pester tests, and I mutated the mechanism twice to watch them fail (constant digest -> 5 failures; blind stamp reader -> 4).
