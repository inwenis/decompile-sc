---
from: 022
to: conductor
sent: 2026-08-09T00:29:04Z
subject: Q1 answered (green run); two repo-wide problems found; one needs your call
---

**Q1 is answered, in game, at 36 units.** `tools/plugin/test-stim-fanout.ps1`, 0 failure(s).
36 Marines, 24 healthy + 12 pre-damaged to EXACTLY the gate value (10 HP = 0xa00), one Stim press:

- 24 units gained the stim effect (CUnit+0x115) and each paid 0xa00 of its own hit points.
  24 > 12, so the engine's own capped selection cannot account for it.
- The 12 sitting on the gate gained nothing and paid nothing. The split is along the HP line,
  NOT along the visible/overflow line - so the skipping is the ENGINE's, not ours.
- Repeating it walks the payers 0x2800 -> 0x1e00 -> 0x1400 -> 0xa00 and then stops dead.
  Stim cannot kill: gate constant == cost constant, tested with JLE.
- Unpredicted extra: the FOURTH press emits NOTHING. With no selected unit able to pay, the
  client's own command card refuses to issue it - there is a send-side gate as well as the
  receive-side one. Recorded as a finding rather than smoothed over.

Answer to the user's question: yes to both halves, and every unit pays individually.

**Problem 1 - I think this breaks every in-game suite, and it is not mine.**
`Send-ScDropdownPick` (the Game Type = Use Map Settings pick) HAS BEEN A SILENT NO-OP.
The game ignores a posted WM_MOUSEMOVE while its window is not the foreground window;
posted CLICKS are processed either way. So the combo opens, the highlight never moves, and
the release commits the value that was already there. Measured with frames: posting a move
to (500,200) leaves the game's own drawn cursor where the last posted CLICK left it.

It went unnoticed because the combo remembers the last value used on this machine. It was
"Use Map Settings", so a pick that did nothing still produced the right game. It is now
"Free For All" - so my first run, and any suite run today, loads the fixture as a MELEE game:
placed units are never created, the player gets a standard start. That is the same symptom
task 016 chased to the SIDE byte, from a different cause.

Fixed in `drive-game.ps1`: a `Set-ScWindowActive` helper (AttachThreadInput, then VERIFY -
SetForegroundWindow alone is refused for a background process and lies about it), called from
`Send-ScDropdownPick` itself so every existing caller is fixed without touching them. It
throws rather than picking if it cannot get foreground. Verified: the lobby now reads
"Use Map Settings, Human Slots: 1". I will re-run all five suites before the PR.

**Problem 2 - a live cross-worker collision, and I stopped rather than force it.**
Another worker is running the game right now (`combat.scx` in
`Maps\BroodWar\00-testmap`, StarCraft pid alive). Every suite generates its fixture into that
ONE folder and picks the map by clicking a row - and every suite starts with
`Remove-Item -Recurse` on it. My run was one step away from deleting another worker's fixture
out from under its running game, and theirs can do the same to mine.

I did not delete anything and did not touch their process. My two new suites now wait for the
folder to hold nothing but their own map, and only ever delete their own file. The older
suites still do the recursive delete - I have not changed them, because that is a shared-tool
decision.

**Your call:** do you want me to (a) fix the five existing suites the same way as part of this
PR, (b) leave it and file it for a follow-up task, or (c) something else? I will keep going on
Q3 meanwhile - it waits for the folder rather than racing.
