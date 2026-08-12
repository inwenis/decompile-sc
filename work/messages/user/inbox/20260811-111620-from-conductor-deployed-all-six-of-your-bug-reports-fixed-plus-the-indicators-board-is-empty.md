---
from: conductor
to: user
sent: 2026-08-11T11:16:20Z
subject: DEPLOYED: all six of your bug reports fixed, plus the indicators. Board is empty
---

# Everything you reported this morning is fixed and on your shortcut

Six reports, all closed. Go double-click it.

| you said | now |
| --- | --- |
| "the 5'th slot is empty" | the 5th icon fills, and a **+N** appears when more is queued than the strip can draw |
| "the group display doesn`t get updated when some die" | fixed — the row re-flows to your live units |
| "no queue indicating the queue" for upgrades | the queue is shown |
| "i can`t select building with double click" | works |
| "i can`t use ctrl or shift to modify building group" | works |
| "control group with buildings only shows 1" | works — recalls all of them |

Plus the thing you asked about paging: the row now shows **page i/j**, so you can see there are more units than the twelve on screen.

**And a bonus:** tests now steal your screen for about four seconds at launch instead of the entire run.

# Two things worth knowing

**1. The page indicator had been BUILT and invisible for weeks.** It was spliced in, written to, and its test passed — but the box was nine pixels tall and the game refuses to draw text taller than its box. The test was only ever asking the plugin what the plugin had written. You found it by asking me how to page.

**2. The upgrade card still lights an already-queued upgrade.** That is the mechanism that lets you queue at all, so it is not a bug exactly — but the display says HOW MANY are queued, not WHICH. Marking them is a bigger change to the card. Tell me if it bothers you in play.

# The wider screen: stopping, with a real answer

Merged as research, off by default, and the answer is a documented no.

- The engine CAN compose a wider picture — that part works and is committed.
- The playfield geometry does not render correctly, and the investigation established WHY the question "which part is broken" has no answer: the ~120 changes are only coherent together, so it cannot be bisected.
- **But the real blocker is not the corruption.** The windowing helper we launch through crops to 640 columns and always has. Even a perfect wider picture would put zero new pixels on your monitor.

So the decision I put to you still stands, and it is genuinely yours: the only route that would show those columns is true fullscreen, which switches your 4K desktop to 800x600 and rearranges your desktop icons. My honest recommendation is to leave it — you would be playing at 800x600 on a 4K screen to gain 160 columns of map.

Nothing is lost by stopping: it is written up as a measured account, so picking it up later starts from facts rather than an estimate.

# Board

**Empty.** No open tasks, no open PRs. Five issues remain filed for later, all test-harness quality, none affecting your game:

- #29 removes the last window flicker
- #44 13+ buildings vs the unit row, never tested
- #45 a Patrol test that has been passing by accident since it was written

GitHub Actions billing is still the one thing only you can fix; local checks have covered every merge in the meantime.
