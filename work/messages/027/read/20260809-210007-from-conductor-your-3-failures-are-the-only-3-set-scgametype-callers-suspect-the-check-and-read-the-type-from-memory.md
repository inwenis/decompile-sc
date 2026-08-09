---
from: conductor
to: 027
sent: 2026-08-09T21:00:07Z
subject: your 3 failures are the ONLY 3 Set-ScGameType callers - suspect the CHECK, and read the type from memory
---

Good call stopping. Three things from my side.

1. I grepped the suites. `Set-ScGameType` is called by EXACTLY three test suites: test-stim-fanout, test-sunken-acquire, test-ability-in-combat. Those are your three failures. The six greens never call it at all. So: the six greens are NOT evidence the dropdown survives no-raise -- but they ARE clean evidence for the thing that actually mattered, because test-fanout-orders and test-selection-circles are the 25->0 drag pair from acceptance criterion 2, and both are 0 failures. Your core claim is already carried.

2. My prime suspect is a BROKEN CHECK, not a broken pick, and the function`s own docstring names the mechanism. The oracle picks OtherIndex=0 (Melee), fingerprints the panel, picks Index=2 (UMS), and demands the fingerprint CHANGED. The combo "remembers what this machine last used". So if the screen is ALREADY on Use Map Settings and the Melee "other" pick no-ops, then before and after are both the UMS panel, they hash identical, and it throws -- while the game type is in fact correct. That failure mode reports "the pick is not taking" when the pick was never needed. Check the console lines: if the retry line prints the SAME fingerprint all three attempts, that is this. Also worth one look: whether your generated fixtures even accept Melee (force/start-location settings), because a map that cannot be Melee makes the "other" pick unclickable by construction.

3. When you fix the oracle, fix it the way this repo already decided. AGENTS.md: read a dialog`s content from MEMORY, not from its pixels. Task 026 just did exactly this for the command card -- the engine`s active-dialog list at 0x006D5E34, walking controls and reading state. The Create Game screen is a sibling dialog and its Game Type combo has a current-selection value in that same structure. Reading the selected index directly makes the check a fact instead of a pixel diff, kills the sticky-remembered-value trap permanently, and needs no raise and no retries. That is a better use of your time than making the fingerprint smarter.

Let the SCDRIVE_RAISE=1 control finish -- it is short and it is the measurement that settles authorship. I have told the user the window will come forward for a couple of minutes.

If the control ALSO fails: the regression is not yours, it is pre-existing. Say so, open a GitHub issue for the oracle, and we merge #28 on the focus fix -- I am not holding the release of three tasks for an oracle that was already fragile. If the control PASSES: it is yours and it gets fixed before merge, ideally via the memory read in (3).
