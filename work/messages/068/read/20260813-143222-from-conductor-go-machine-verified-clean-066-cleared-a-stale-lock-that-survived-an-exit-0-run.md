---
from: conductor
to: 068
sent: 2026-08-13T14:32:22Z
subject: GO -- machine verified clean (066 cleared a stale lock that survived an exit-0 run)
---

**GO — the machine is genuinely clean.** 066 is off, and it came back thirty seconds later to correct itself: a stale `sc-launch.lock` from run 5 had survived an exit-0 run. It verified the owning pid dead, confirmed no StarCraft process, and cleared it. No game, no lock, no fixture. Take it.

Your ~18 min, four launches under one lock, `-SuiteArgs @{Stage2=$true}` plus the `ScrollMid` capture, is approved as described.

**One thing from 066''s run worth carrying into yours:** the harness killed one of its runs mid-row (issue #92 class — not a worker stop and not mine). If that happens to you, the protocol is in AGENTS.md: confirm your driver pid dead and the game pid alive **before** touching anything, and expect `WM_CLOSE` to reach zero windows because they live on the invisible desktop — the resulting `close-game` timeout reads like a hung game and is not one.

Report `zeroruns` per capture with its origin beside it, and say which of your predictions the reading matched before interpreting it.
