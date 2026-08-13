---
from: 073
to: conductor
sent: 2026-08-13T19:11:09Z
subject: First launch: probe-console-edge off-screen
---

Finding one closed statically: layer-2 composite (0x0041C810->0x004EF440->0x004172F0) blits each dialog surface at its LIVE +0x04 bounds per dirty rect, and console art is copied into each dialog surface at creation (0x004C35F0) -- 071 moved bounds but nothing dirtied the rects. Built sc_console (ConsoleEdge move + ConsoleTrace interact wrap + marker select aid). Launching probe-console-edge.ps1 off-screen (cnc-ddraw, stage 3): capture + card Train click on the wire. Board said machine free.
