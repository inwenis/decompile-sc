---
from: conductor
to: user
sent: 2026-08-11T08:04:24Z
subject: all six logged and assigned - one is a real bug, the rest are 'we shipped the engine and forgot the dashboard'
---

All six taken, split across two tasks by which code owns them. Thank you for playing it properly — this is the most useful hour of input the project has had.

# The one that is an actual BUG

**"more than 12 units selected and some die - the group display doesn`t get updated"**

You are looking at a display that is actively lying about your selection, in a fight, which is exactly when you need it. Everything else on your list is a missing indicator; this one shows you wrong information. It is now the top priority of task 033, ahead of the nice-to-haves, and if it is ready before the rest I will ship it on its own.

# The theme in the other five

We built the machinery and forgot the dashboard. Every one of these is the game DOING the right thing while telling you nothing:

| what you saw | what is actually happening |
| --- | --- |
| 5th queue slot always empty | The plugin deliberately keeps the game`s own queue at FOUR so the game keeps accepting clicks — that is what makes >5 work at all. The queue is right; the strip just never draws a fifth icon. Fixing it on the display side. Raising it to five would silently break the whole feature. |
| queued upgrades invisible, buttons stay lit | The buttons staying lit is the mechanism that lets you queue at all. But nothing shows WHAT you queued, so it reads as confusing rather than as working. |
| no way to tell the unit row has more pages | Same gap you found earlier — the design notes chose "paging plus an indicator" and only the paging got built. |

All three go to task 033 with the `+N` and `page i/j` work, since they are the same screen region and the same text drawing.

# The three selection ones

**Double-click, shift/ctrl-click, and control-group recall showing 1** — task 036, just cut.

The honest diagnosis: task 024 made the drag BOX work with buildings and nothing else. Every other way you can select a group still hits the vanilla one-building-at-a-time rule. That was scoped deliberately at the time and it turns out to be exactly half a feature — you found the other half by using it.

I told 036 to MEASURE each of the three before fixing anything, because "shows 1" could be three different bugs: the game refusing to send, the game dropping it, or the selection being correct and only the display wrong. Those have completely different fixes and the symptom cannot tell them apart. If the control-group one turns out to be a display problem it belongs to 033, and I will route it.

# Where that leaves the board

Five tasks running: 033 (all the display fixes + the stale-row bug), 034 (wider screen attempt), 035 (the five GitHub issues incl. the launch focus-steal), 036 (building selection), and everything else merged.

Nothing needed from you. Keep playing and keep reporting — you are finding things no test does, because the tests were written by the people who already knew how the features work.
