---
from: 033
to: conductor
sent: 2026-08-11T09:17:40Z
subject: PR #41 open: all five, four proven in game, one stated as unproven
---

**https://github.com/inwenis/decompile-sc/pull/41** — `pr:` is in the task file. Four commits; the stale-row fix is `121b556`, first and self-contained, so you can take it early without the rest.

| suite | result |
|---|---|
| hooktest (parts [10] and [19] extended) | 0 failures |
| test-production-queue.ps1 (own folder 00-t033) | 0 failures |
| test-hud-row.ps1 | 0 failures |
| test-group-production.ps1 -Arm feature | 0 failures |
| test-group-production.ps1 -Arm baseline | 0 failures |

**`page i/j` now draws — that is no longer fixed-but-unproven:**

```
HUDROW show n=36 page=2/3 ... indicator="36 units  13-24  (2/3)"
                 indLinked=1 indVisible=1 indBounds=(32,9,180,25) indInk=2368
```

**The off arm is a measurement, not a silence.** From the row run, which never passes the flag: `queueind=0` and `QIND ... linked=0 visible=0 text="" ink=-1 refInk=1330` — `refInk` non-zero in the same line is what makes `linked=0` mean something.

**The group negative arm you asked for**: with the fan-out off, `mode=0` — asserted, not merely unobserved.

**A THIRD defect of mine, and it is the one worth reading.** The first live group run drew `"4 bldgs  4 queued"` into a box **22 pixels wide** — clamped to the 34px wireframe button it anchors to. `mode=2 linked=1 visible=1 text=... ink=352`: five correct readings describing a display the player cannot read. **A clipped string is still ink.** So the ink oracle you liked catches "nothing was drawn" and does NOT catch "not all of it was drawn" — the two directions of the same box mistake, and only one of them is loud. Fixed by sizing the box from the string; both suites now assert the box fits what it holds; `research/status-pane-text.md` 5.1 has it with the live numbers. After the fix: `bounds=(40,9,159,25) ink=1904`.

**One thing NOT proven, and I want it in your review rather than discovered later:** `+N upg` has no in-game arm. It is covered offline and rides the same frame path the other three modes are proven on, but no live run has queued an upgrade and read it back. That arm belongs in `test-upgrade-queue.ps1` and is not in this PR. Everything else the user reported is proven in a real game.

Also honest about scope I did NOT take: the card still lights an already-queued upgrade (their "they don`t dissapear from the shop window"). That is task 029`s unblock working as designed; this PR says how many are queued, not which, and marking them is a card change. Your call whether it becomes a follow-up.

Flag for the deployed launcher: **`-QueueIndicator 1`**, already added to `tools/deploy.ps1``s recipe. Off by default everywhere else and refused in observe/shadow.

No stranded processes and no fixture left behind: my folder `00-t033` is gone and every run asserted its own game exited and its map was removed. The StarCraft running now and the launch lock belong to task 036, untouched.
