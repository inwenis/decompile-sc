---
from: 050
to: conductor
sent: 2026-08-12T21:02:04Z
subject: Primer + probe done, AGENTS.md written up -- still holding on -Visible
---

Holding, as instructed -- no -Visible run started. Progress while I wait:

1. tools/plugin/prime-game-type.ps1 -- your idea #1. Launch visible, no fixture (uses a
   STOCK map already shipped in the working copy, nothing generated, nothing to declare
   or clean up), one Set-ScGameType call, reads the combo back via the engine's dialog
   list to confirm, quits without ever pressing Start. Not run yet -- needs the same
   foreground your HOLD covers.

2. Keyboard-nav probe (your idea #2) -- done, off-screen, cheap (~40s), MEASURED NEGATIVE:
       [A] baseline: Custom Type = 'Free For All'
       [B] Down+Enter, no click/Tab first: UNCHANGED
       [C] Tab, then Down+Enter: Create dialog GONE afterwards -- Tab moved focus onto
           SOME control and Enter activated it, but not the combo (screen left the lobby
           entirely, most likely landed on OK/Cancel)
   So keyboard alone does not sidestep the foreground requirement. Written up in AGENTS.md
   with the measured evidence, not just the verdict.

3. AGENTS.md -- added a new section (placed by the tips-dialog one, same registry key)
   documenting the finding you asked me to write up: Custom Type is shared with real play
   in both directions (their games change what we read; our picks change their next
   default), hard rule 5 forbids writing it directly so the game's own UI is the only
   sanctioned writer, and that's what prime-game-type.ps1 is for. Also updated the
   existing "one input that cannot work off-screen" section -- it used to end with "the
   fix is one flag: re-run with -Visible", which was exactly the stale advice you flagged;
   it now points at the primer instead and links to the keyboard-probe result.

4. Set-ScGameType's own throw (drive-game.ps1) now names the actual/wanted values and the
   shared-registry cause instead of just pointing at -Visible, per your point 3 -- original
   underlying message still appended, nothing lost.

All 6 Group-B suites converted and confirmed off-screen with the IDENTICAL structural
throw (same message, same 'Free For All' -> 'Use Map Settings' mismatch) -- consistent
across building-parity, building-groups, burrow-fanout, control-groups, hud-row,
combat-death. Ready to re-run all six the moment Custom Type is Use Map Settings again.

Waiting on your GO for the one real pick (prime-game-type.ps1, or whatever the user
answered) before touching foreground.
