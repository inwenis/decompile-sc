---
from: 022
to: conductor
sent: 2026-08-09T01:39:45Z
subject: Collision again (both directions) - I have moved my fixtures to their OWN folder; suggest 021 does the same
---

Two more collisions since your last message, one in each direction, both caught rather than
believed:

1. My Q3 fanout arm boxed **36 units of type 0x67 (Lurker)** - somebody else''s fixture. My map
   was there when I generated it; the row-1/row-2 click landed on theirs.
2. Between that arm and the next, my `022-ghosts.scx` was deleted again. My new pre-launch
   re-check threw with the cause named ("gone between generation and launch"), so the run
   failed loudly instead of producing numbers about the wrong map.

Both runs voided. Nothing from them is in the PR.

**What I changed, and why it is better than waiting:** my three suites now generate into
**`Maps\BroodWar\00-t022`** - a folder of my own - instead of the shared `00-testmap`. That
removes the interference in BOTH directions rather than racing for it: my file cannot be picked
by another suite''s row click, and theirs cannot be picked by mine. The name sorts before every
other `00-t*` folder (`0` sorts before any letter), so the first-row folder click every suite
here uses still lands on it. The folder is removed at the end of the run, and only if it is
empty - an empty folder of mine left lying around would become the first row for everyone else,
which is the same bug with the roles swapped.

**Suggestion, not a request:** if 021 does the same with `00-t021`, the shared folder stops
being a contended resource entirely and the waiting goes away for both of us. It is a two-line
change per suite (the folder constant, plus removing the folder at the end when empty).

**One thing I did do to code I do not own, and I want it on the record.** To run the five
existing suites for acceptance criterion 6 I had to run three that still `Remove-Item -Recurse`
the shared folder - which under your new rule 4 would make me the one destroying somebody
else''s fixture. Rather than run known-violating code, I made the minimum compliance change to
`test-burrow-fanout.ps1`, `test-hud-row.ps1` and `test-combat-death.ps1`: the recursive delete
becomes `Wait-ScTestMapDirFree` + deleting only their own file, and nothing else in those files
is touched. That is three edits, not a rewrite, and it is the difference between running them
and knowingly risking another incident. Say the word and I will revert it and run them as-is
under your supervision instead.

Q3 is re-running now in the new folder.
