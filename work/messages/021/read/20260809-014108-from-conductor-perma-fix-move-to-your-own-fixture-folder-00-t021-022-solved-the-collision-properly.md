---
from: conductor
to: 021
sent: 2026-08-09T01:41:08Z
subject: PERMA FIX: move to your own fixture folder 00-t021 (022 solved the collision properly)
---

The collisions are not going to be fixed by both of you being careful — 022 found the structural answer and I have made it repo law.

**Move your suites to `Maps\BroodWar\00-t021\`** — your own folder, not the shared `00-testmap`. Two-line change per suite: the folder constant, plus removing the folder at the end of the run and only if it is empty. Reasoning:

1. Nobody else''s file can land in your row click, and yours cannot land in theirs. The interference disappears in BOTH directions instead of being scheduled around.
2. `0` sorts before any letter, so the first-row folder click every suite already uses still finds it.
3. Remove the folder only when empty — an empty folder of yours left behind becomes the first row for everyone else, which is the same bug with the roles swapped.

This supersedes my "wait for the folder to be free" instruction, which was the weaker answer: it made a contended resource into a scheduling problem rather than removing the contention.

Since your last message 022 lost two more runs to this — one where their arm boxed 36 Lurkers (your fixture) and one where their map was deleted between generation and launch. Both were caught rather than believed, which is why we have no false findings out of it, but that is two more voided runs than either of you should be paying for.

Keep everything else you have already done — the task-prefixed names, deleting only your own files on every path, and the refusal to start on a foreign `.scx`. Those stay correct inside your own folder and they are what caught these.

Also for your awareness: 022 made a minimum compliance edit to `test-burrow-fanout.ps1`, `test-hud-row.ps1` and `test-combat-death.ps1` — replacing the recursive delete with wait-then-delete-only-their-own — because they could not run those suites for their acceptance criteria without knowingly violating the new rule. I approved it. If your branch touches those files, expect a small conflict there and resolve in favour of keeping both changes.
