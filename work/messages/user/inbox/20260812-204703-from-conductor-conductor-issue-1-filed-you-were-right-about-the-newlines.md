---
from: conductor
to: user
sent: 2026-08-12T20:47:03Z
subject: conductor issue #1 filed -- you were right about the newlines
---

Filed: **https://github.com/inwenis/conductor/issues/1**

You diagnosed it correctly. The bodies I write are hard-wrapped at about 95 columns because they are also files someone reads in a terminal, and the console appears to keep those newlines instead of folding them the way Markdown says to — so a paragraph breaks at *my* column positions rather than at the panel width, and long lines then soft-wrap on top of that. The issue names both mechanisms that produce it (`white-space: pre-wrap`, or a Markdown renderer with `breaks` turned on) as hypotheses to check, and flags the two things a fix must not break: fenced code blocks, and the indented blocks of Windows paths I send you.

I did not read the conductor source to diagnose it — that repo is off-limits to everything in this one by hard rule, and `gh --repo` never touches the checkout.

Also changing on my side: I am writing this one unwrapped, so the console does the wrapping. Tell me if it reads better.

## Board, as of 20:47Z

| # | task | state | needs you? |
| --- | --- | --- | --- |
| 039 | fifth slot / group line | **merged and deployed** | play it and tell me if it is right |
| 050 | six suites that steal your screen | running — all six converted, off-screen runs in progress | no |
| 051 | does save/load survive the mods | running — holding launches while 050 has the game | no |
| 048 | the same overlap bug, latent, in the 12-icon row | queued, spec written | no |
| 049 | off-screen verdict table | paused until 050 lands, since 050 changes the answer | no |

Two issues opened against `decompile-sc` as well: **#58** for the third fifth-slot rendering nobody photographed, and the pre-existing **#48** build warnings are still open and still harmless.

One consequence you might like: 050 has already converted `test-hud-row`, the suite I asked you to give up three minutes of screen for this morning. If its off-screen run passes, that request is dead and no test needs your monitor again.
