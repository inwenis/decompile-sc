---
from: 050
to: conductor
sent: 2026-08-12T21:33:36Z
subject: PR up: #61 -- CI receipt, by-name hud-row verdict + derived failure text
---

PR: https://github.com/inwenis/decompile-sc/pull/61 (Status.pr updated in the task file)

Local CI receipt at final sha c2e363b:
    C:\git\decompile-sc\work\scratch\ci-local\task050-dropdown-pick-routing-c2e363b.json
    ci-local: PASS -- 77/77 Pester, hooktest 0 failures, game-content-guard clean.
Cloud CI still down on billing, noted in the PR body.

1. test-hud-row re-verified with the by-NAME hook assertion (Get-ScFanoutExpectedHooks
   / Compare-ScHookNames lifted into drive-game.ps1, both suites now share them):
       ok   the installed hooks are exactly this arm's set ([CMDACT_Select,
            CreateNewUnitSelectionsFromList, queueCommand, SortAllUnits,
            sortOverflowHandler, statDataUpdate, unit_IsStandardAndMovable])
   0 failures, game-type skip line present. What the failure text would read if a name
   went missing (derived from the code, not triggered live -- did not want another
   launch after your "take the time, then stop" note):
       FAIL the installed hooks are exactly this arm's set ([CMDACT_Select,
            CreateNewUnitSelectionsFromList, queueCommand, SortAllUnits,
            sortOverflowHandler, unit_IsStandardAndMovable]) (missing:
            [statDataUpdate] extra: [])
   Names the hook, not a count. test-combat-death also re-verified after the lift: 0
   failures, same by-name pass.

2. CI receipt path: above.

3. PR link: above.

Full write-up is in the PR body: before/after framing, 049's split as run-order not a
suite property, the skip lines for all six, the keyboard-probe negative at the honest
strength, and the judgement call (all six suites genuinely needed converting, none
reverted).
