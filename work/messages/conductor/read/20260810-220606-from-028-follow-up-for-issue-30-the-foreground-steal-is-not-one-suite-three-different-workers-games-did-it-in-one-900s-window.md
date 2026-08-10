---
from: 028
to: conductor
sent: 2026-08-10T22:06:06Z
subject: follow-up for issue #30: the foreground steal is not one suite - three different workers games did it in one 900s window
---

PR #31 is merged, thank you. One data point that arrived after I sent the PR, because the watcher kept sampling past my own run: it sharpens what I flagged and points AWAY from my suite.

Full 900s log, one line per change (mine is pid 39444; the rest are other workers):

  22:50:30  StarCraft pid=39444   <- my run 3 (Game Type pick is here)
  22:51:54  WindowsTerminal
  22:51:54  StarCraft pid=39444
  22:54:04  WindowsTerminal
  22:56:30  StarCraft pid=39796   <- my hud-row regression run
  22:58:07  WindowsTerminal
  22:59:43  StarCraft pid=41936   <- NOT mine
  23:01:34  WindowsTerminal
  23:01:35  StarCraft pid=41936   <- NOT mine
  23:01:48  WindowsTerminal
  23:03:54  StarCraft pid=40084   <- NOT mine

FOUR different game processes, at least two of them another worker`s, all taking the foreground and holding it for minutes in the same window. So this is not "task 028`s suite raises the window": it is every game launch tonight. Two shapes worth separating for whoever picks up #30:

1. the raise itself may still be the one allowed one (Send-ScDropdownPick, for the Game Type pick) - every suite in that list picks a game type;
2. what looks wrong is the HAND-BACK, not the borrow: the window is not being given back, and no "could not hand the foreground back" warning was printed on my run, so MakeForeground is reporting success while the game keeps or re-takes the foreground. That is a different bug from the one 027 fixed, and it would reproduce on any suite that calls Set-ScGameType.

I have not investigated further - out of scope for 028 and my worktree is merged. Raw logs are at work/scratch/028/foreground*.log in my worktree if you want them before it is pruned; the same lines are in PR #31`s body.

Idle: no game of mine running, launch lock released, fixture folder gone.
