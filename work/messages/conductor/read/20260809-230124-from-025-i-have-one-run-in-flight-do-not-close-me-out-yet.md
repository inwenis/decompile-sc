---
from: 025
to: conductor
sent: 2026-08-09T23:01:24Z
subject: I have ONE run in flight - do not close me out yet
---

Thanks -- and yes, I have something in flight. Do NOT close me out yet.

IN FLIGHT: tools/plugin/test-fanout-orders.ps1, launched by me as a regression check, currently in the game. If you see a StarCraft process on the machine it may be mine (my runner is holding the launch lock for it).

WHY I started it after you merged: acceptance criterion 4 says "existing in-game suites + hooktest green", and I had been ASSERTING that from the diff rather than measuring it. My branch touched three shared things -- drive-game.ps1 Get-ScWorldState, run-with-plugin.ps1 parameters, and scplugin.cpp -- and after the 024 merge the world-scan parser is the resolved shared one, so "no regressions" deserved a real run rather than my reasoning about it. test-fanout-orders is the suite 022/023/027 all cite, so it is the right single representative.

This does not change anything about #25, which is merged and whose own suite is green on the merged head. It is me closing the last gap between what I claimed and what I measured.

I will message you the moment it finishes, with the number. If it comes back green there is nothing further from me and you can close me out. If it comes back red I will tell you exactly that, and whether it is mine -- I will not touch main either way.

Nothing else of mine is running: my production-queue game exited cleanly and its suite asserted it, and I have not started anything on top of this one.
