---
from: conductor
to: user
sent: 2026-08-09T21:08:05Z
subject: status: 4 features done and waiting on 1 test-harness fix (027)
---

# Status

## Short version

Four features are BUILT. None are merged yet, because all four are queued behind one fix: making tests stop stealing your focus. That fix is close -- 8 of 9 test suites green, one regression found and fixed, re-running now.

## The four features waiting

| task | what you get | PR | what is missing |
| --- | --- | --- | --- |
| 024 | box-select same-type buildings as a group | #24 | 2 in-game runs |
| 025 | queue more than 5 units at a building | #25 | 1 in-game run |
| 026 | the cloaked-ghost answer | #27 | 2 in-game runs |
| 027 | tests stop stealing your focus | #28 | final sweep, running now |

Every one of them needs the game launched to finish. I froze all in-game runs when you told me tests were yanking your window away, which is why they are all stacked up.

## Your cloaked ghost -- answered

Cloak was on the Ghost`s command card at slot 7, greyed out. Cause: our test-map generator wrote the tech-unlock table in the wrong index order, so only Stim ever actually got unlocked. A bug in OUR test tooling, not in your game and not in the mod. Details in PR #27.

## The focus fix (027) -- what actually happened

1. Cause was OUR OWN earlier fix. Task 022 forced the game window to the front before every click, believing the game ignored mouse input while in the background.
2. That belief was wrong. 027 checked the game`s own disassembled window procedure: it stores mouse position unconditionally, with no foreground check. Then proved it live -- a posted mouse move registered and drew while your window kept the foreground.
3. Worse, the raise was actively harmful: activating the window makes the game re-grab and CLIP your cursor to its rectangle.
4. So the raise was deleted. 6 suites went green in the background, including the two drag-heavy ones that were the original reason the raise was added.
5. But 3 suites broke -- the only 3 that use the Game Type dropdown. I guessed the test`s verification was at fault. I was wrong. 027 ran a control with the old behaviour, and it passed, which proved the regression was real and was 027`s.
6. Real cause, and it is a genuine Windows rule: a dropdown is press-and-hold, the game calls SetCapture on button-down, and Windows only grants mouse capture to the FOREGROUND window. World drag-boxes do not need it; dialog dropdowns do.
7. Fix: only the dropdown helper raises, for one pick, then hands focus straight back to you.

Cost to you: about 2 seconds of flicker during the menu, in 3 of the 9 suites, instead of the entire run of all nine holding your screen hostage. I filed issue #29 to remove even that later by reading the setting from game memory instead of clicking it.

## What happens next, in order

1. 027 finishes the 9-suite re-run + offline CI -> I merge #28 -> I deploy to your desktop shortcut.
2. I release 024, 025, 026 onto the no-raise build. They run their remaining in-game runs without touching your screen.
3. I merge each one and deploy after each.

## Not started yet

Queuing upgrades, and the wider screen. Both still queued behind the above.

## One thing only you can fix

GitHub Actions billing is blocked on the repo. Not urgent -- I am running the same checks locally and recording receipts, so nothing is stuck on it.
