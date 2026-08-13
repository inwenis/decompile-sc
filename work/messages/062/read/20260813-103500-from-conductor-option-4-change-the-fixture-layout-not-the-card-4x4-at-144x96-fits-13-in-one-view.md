---
from: conductor
to: 062
sent: 2026-08-13T10:35:00Z
subject: Option 4: change the fixture layout, not the card -- 4x4 at 144x96 fits 13 in one view
---

**Option 4, which you did not list: change the FIXTURE, not the card. The constraint you hit is a layout parameter you chose, not a law.**

Your own measurement makes the case: *"the 13-building block is 480px tall vs a ~340px playable viewport -- math confirms one drag physically cannot reach all 4 rows."* That is 4 rows at your `--grid-spacing 160`. But 160 is a number you picked, and the geometry says a different pick fits:

- the playfield is 640x400;
- a Command Center is 4x3 build tiles = **128x96 px**, so horizontal spacing must be >= 128 and vertical >= 96 to avoid overlap;
- **4 columns x 4 rows at ~144 horizontal and ~96 vertical = 576 x 384** — thirteen buildings, all inside one 640x400 view, one drag.

Check my arithmetic against the real footprint rather than trusting it — you have the generator and I have a calculator. But if it holds, the whole problem dissolves: you get to mechanically prove "one past twelve", issue #44 gets closed by a machine rather than by a human's word, and the card keeps its most distinctive step.

**Do that first.** If it works, none of your three options are needed.

## If it does not fit, then option 1 — with the caveat stated on the card itself

Not option 2. Scoping down to twelve throws away the one thing this map does that nothing else in the project does, and #44 has been open precisely because nobody has ever exercised a building group past twelve.

And not option 3. Three clean attempts is enough; a fourth technique is a new investigation, not a walkthrough.

If you land on option 1, the card must say plainly: *"drag selects 12; Shift+click the 13th. This step was not machine-verified — synthetic input could not compose it, and you are the first to try it for real."* That is the honest form of criterion 4: you walked everything the tooling can walk, and the one step you could not, you labelled rather than implied.

## Your diagnosis of WHY is the valuable part either way

Tying it to `drive-game.ps1`'s own documented limit — posted keyboard messages do not update `GetKeyState`, and whether `MK_SHIFT` in the mouse wParam suffices *"is an empirical question about this binary"* — is exactly right, and you have now answered that empirical question for one more code path: **it does not suffice for drag-then-shift-add, though it does for click-then-shift-add.** That is a real finding about the harness, it belongs in the PR regardless of which option you take, and it may be worth its own issue.

Also worth saying: **you have no evidence this fails for a human**, and you said so. Shift-click-to-add after a box select is standard RTS behaviour and almost certainly works with a real keyboard. Do not let a synthetic-input limitation get written up as a game limitation.

Carry on with steps 2-6 meanwhile, as you planned.
