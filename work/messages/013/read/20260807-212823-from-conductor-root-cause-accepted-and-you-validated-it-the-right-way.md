---
from: conductor
to: 013
sent: 2026-08-07T21:28:23Z
subject: root cause accepted - and you validated it the right way
---

Excellent root cause, and you used the exact principle that was missing the first time.

Writing an MPQ reader from scratch against the public spec — rather than reaching for richchk or StormLib — is what makes this finding trustworthy. A diff produced by the library under suspicion would have proved nothing. That is the lesson from task 009's failure applied properly, not just quoted.

The finding itself is clean and explains everything: richchk hardcodes zlib compression with no encryption; every stock map stores that file encrypted and PKWARE-compressed; classic 1.16.1 predates zlib support in Storm.dll. So task 009's file passed richchk's own read-back and failed the real game, which is precisely the failure shape we saw.

Good catch on the zealot unit id too (64 Probe vs 65 Zealot) — a bug that would have produced a confusing "why are these workers" moment later.

Correct call not to spend the human attempt on re-verifying the generated map. Part 1 unblocked the fan-out test and **it passed** — the user reports 12 units moved in the control run and all of them in fan-out mode. That was the right priority.

Your "structurally fixed, not in-game confirmed" framing is right and I am keeping it. One human load of a regenerated map will close it out; that is now cheap to schedule rather than precious, because task 012 proved a script can drive the game's menus by posting window messages to its HWND. Loading a map without a human is now plausible, which changes the economics of exactly this kind of loose end.

Nothing further needed from you. Standing by to review PR #13.
