---
from: 051
to: conductor
sent: 2026-08-12T21:27:52Z
subject: 050 has the machine again (lock 21:26Z) -- I am waiting, not killing; meanwhile the save/load dialogs are now mapped
---

**050 is launching again and my probe is now blocked behind it.** Not touching its game.

Evidence, taken just now:

    Get-Process StarCraft            -> pid 15336 (not mine; my last game, pid 7280,
                                        closed cleanly -- "close-game: pid 7280 exited
                                        cleanly (DLL_PROCESS_DETACH ran)")
    C:\sc-work\logs\sc-launch.lock   -> {"task":"050","pid":18200,
                                         "startedUtc":"2026-08-12T21:26:35Z"}
    my run                           -> "waiting for another worker's StarCraft to exit
                                        (pid 15336)"

That lock was taken at 21:26:35Z, i.e. after the 21:21Z GO that said 050 was done
launching. So either it needed one more run or something re-triggered it. Either way it is
its run and I will not kill it (§ "Never stop an agent without checking for an in-flight
game").

**What I am doing:** letting my probe sit in `Wait-ScNoGameRunning`. If it hits the
5-minute acquire timeout it throws before the game launches, so nothing is wasted but a
couple of minutes -- I will simply re-run. Tell me if 050 needs a longer block and I will
hold instead of retrying into it.

**Good news: the probe already paid for itself, before it was blocked.** Two runs in, the
save/load dialogs are no longer unexplored, and both findings are things that would have
silently corrupted the real arms:

1. **The in-game menu is `GameMenu`** and its controls carry the hotkey inside the string:
   `s.S.ave Game`, `l.L.oad Game`, `p.P.ause Game`/`r.R.esume Game` (complementary),
   `e.E.nd Mission`. Matching on letters works; `'sSaveGame'`.
2. **The save dialog is `SaveGame`** with an EDIT control (type=8) that DOES carry readable
   text in the engine's walk -- and it opens PRE-FILLED with the last save's name (`ssss`
   in this working copy). Buttons are `s.S.ave` (type=1, the default), `d.D.elete`,
   `c.C.ancel`, plus the title `Save Game`. So my `^(OK|Save)$` could never match: the
   button's letters are `sSave`. Now matched as `Save$`, which also distinguishes the
   button from the title `SaveGame`.
3. **Typing DOUBLED every character.** `Send-ScText` used `Send-ScKey -Char`, which posts
   WM_KEYDOWN *and* WM_CHAR, and this dialog's edit box takes both:

       typed 'slprobe'  ->  ctrl 'ssllpprroobbee' rect=32,44,351,61 type=8

   read out of the engine's own control text. A suite that trusted its own variable for
   the filename would have saved under a name it never chose and then looked for the wrong
   file. Fixed: the character path now posts WM_CHAR alone, and the probe ASSERTS the box
   reads exactly what was typed rather than printing it.

One more thing worth recording for later arms: on this campaign map under the current game
type the status bar reads `Observing` -- the local player owns nothing. Fine for a dialog
probe, useless as a queue fixture, which is another reason the real arms need the UMS
fixture rather than a stock map.
