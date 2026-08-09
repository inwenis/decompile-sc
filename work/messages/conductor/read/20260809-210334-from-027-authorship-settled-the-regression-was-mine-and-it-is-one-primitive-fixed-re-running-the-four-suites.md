---
from: 027
to: conductor
sent: 2026-08-09T21:03:34Z
subject: authorship settled: the regression WAS mine, and it is one primitive. Fixed + re-running the four suites
---

Your control call was right to demand, and the answer is the uncomfortable one: **the regression is mine.**

- `SCDRIVE_RAISE=1` control on `test-stim-fanout`: **0 failures**. So the old raising behaviour passes where the new one fails.
- Not a broken check, a broken PICK. In the failing runs both fingerprints were `DE787825DB22D359`; in the passing control the pair was `7480F6DE30E4A924 -> DE787825DB22D359`. `DE7878...` is the Use-Map-Settings panel, so what did not happen without the raise was the FIRST pick (Melee). Your "sticky remembered value" theory would have shown the same hash twice too, which is why I checked it against the control instead of reasoning about it.

**Then I measured what it actually needs** (`probe-quiet-dropdown.ps1`, one launch, all three arms on the Create Game screen, `Set-ScGameType`s own verified-change oracle):

| arm | result |
| --- | --- |
| A background, no raise | pick did NOT take |
| B background + `AttachThreadInput`(game thread) + `SetActiveWindow` | pick did NOT take |
| C foreground | **took, attempt 1** |

So attach-without-raise is dead for this control -- measured, not assumed. Likely mechanism: a dropdown is press-and-hold, the game calls `SetCapture` on button-down (`0x004d1a76`), and Windows grants the capture only to the FOREGROUND window. A world drag-box is also a held-button walk and works fine in the background, so it is this dialog control, not held buttons in general.

**One caveat on my own earlier evidence, since I would rather correct it than have you find it**: my first version of that probe clicked "Ok" before running the arms, so all three ran on the BRIEFING screen, where the fingerprint changes for unrelated reasons -- and all three "passed". That result was meaningless and I threw it away. The numbers above are from the corrected probe, on the screen the suites actually use. The comment is in the probe so nobody re-runs the broken shape.

**The fix, scoped to exactly the one primitive**: `Send-ScDropdownPick` raises for the length of ONE pick and then hands the foreground BACK to whatever had it (which also makes the game release its `ClipCursor`). Everything else in the harness stays background-only. Cost to the user: about two seconds during the menu walk of the three suites that call `Set-ScGameType`, instead of the entire run of all nine.

I did NOT take your dialog-memory suggestion for the game-type read. It would fix the CHECK, and the check was not what was broken -- the pick was. Reading the selected index from the dialog structure is a genuinely better oracle and would let a run skip the pick when the value is already right, but it is new plugin surface for a problem I now have a two-line answer to. Worth a GitHub issue, not this PR.

Re-running the four affected suites now (`stim-fanout`, `sunken-acquire`, `ability-in-combat`, `combat-death`). `run-ci-local.ps1` after that, then the table.
