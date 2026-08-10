---
from: 028
to: conductor
sent: 2026-08-10T22:00:58Z
subject: PR #31 open: cancel-refund proved in a real game, both cases - plus a foreground observation for issue #30
---

PR: https://github.com/inwenis/decompile-sc/pull/31 (closes #26). Acceptance criteria 1-7 all met; details in the PR body.

Headline, because it changes what #26 was about: **the cancel control is TWO controls, and the interesting one is not on the command card.** A queue icon in the STATUS PANE (statdata dialog 0x0068C1F0, control ids 2..6) sends {0x20, displayIndex} and the ENGINE refunds it; the card slot-9 Cancel button sends {0x20, 0xFE} = "the last queued item", which is the PLUGIN`s while it holds any and is the only wire form that can reach an overflow item at all. Both located by reading the owning dialog, both clicked in game, both refunds asserted from memory.

Measured, one launch, 0 failures (three runs; the third is the exact code in the PR):
- plugin-held: CMD id=0x20 bytes=[20 FE 00]; logical 9 -> 8; minerals 2550 -> 2600; PRODQEV cancel-last back=50/0; mineralsRefunded=50, ONCE.
- engine-ring: CMD id=0x20 bytes=[20 01 00]; ring 3 -> 2 from CUnit+0x98; minerals 2450 -> 2500; the plugin`s cancel counter never moved.
- reconciliation spent = built + queued + cancelled holds at every point; plugin mineralsSpent=0.

Two things I got WRONG and the runs caught, both written up rather than quietly fixed:
1. I predicted from the button table that a Terran producer can never show the Cancel button (Land/Lift Off sort ahead of it in slot 9). The live card read says it DOES: Lift Off`s condition requires "not busy producing", the exact complement of Cancel`s, so the same control changes hands the moment anything is queued. Read before/after on one control record in game.
2. My first reconciliation double-counted the unit being built - the engine creates the unit when production STARTS, so an in-progress item is in the world AND in the ring. `built` now comes off the command funnel.

CAN THE UI ADDRESS AN OVERFLOW ITEM? No, not by the strip: it draws the ring and nothing else, five icons for a nine-item queue, and an empty slot`s icon is greyed. The overflow is reachable only through the Cancel button, tail-first, one press each. Stated with evidence in the research doc and the plugin README.

FOR YOU / issue #30, reported rather than claimed: watch-foreground exited NON-ZERO on all three runs. One raise coincides with the Game Type dropdown pick (the one raise AGENTS.md allows), but the window was not handed back promptly - the game held the foreground ~84s and again ~130s. I changed no input code, no hand-back warning was printed, and four other workers with their own StarCraft launches were live on the machine (another pid appears in the same log), so I cannot attribute it from this data. Raw lines are in the PR body under "Foreground - reported, not claimed". Worth a look by whoever owns #30; it cost nothing tonight with the user asleep.

Also: I dropped the multi-building Train add-on as you instructed (never ran it, no data to forward to 030).

Regression: test-hud-row 0 failures (the other suite on the same dialog); run-ci-local PASS (ruff NOT RUN); StarCraft.exe byte-identical to pristine before and after; no stranded process; fixture removed. I am idle now - no game running, launch lock released.
