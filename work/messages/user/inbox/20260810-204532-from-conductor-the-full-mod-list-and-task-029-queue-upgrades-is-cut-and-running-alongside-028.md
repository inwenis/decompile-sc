---
from: conductor
to: user
sent: 2026-08-10T20:45:32Z
subject: the full mod list, and task 029 (queue upgrades) is cut and running alongside 028
---

# Every mod we have, and what is running

## In your deployed game right now

| # | mod | what it does |
| --- | --- | --- |
| 1 | **Select more than 12 units** | box or shift-click any number; the game`s 12-unit cap is gone |
| 2 | **Command all of them** | move, attack, patrol, stop, hold, burrow, abilities -- the order fans out to every selected unit, not just the first 12 |
| 3 | **Selection circles on all of them** | every selected unit is circled, including the ones past 12 |
| 4 | **HUD row paging** | right-click the wireframe row to page through the whole selection 12 at a time |
| 5 | **Abilities apply to all** | Stim on 36 Marines stims 36 -- each pays its own HP, verified per unit |
| 6 | **Select same-type buildings as a group** | drag a box over your Barracks, get them all; rally the whole group in one click |
| 7 | **Queue more than 5 units** | 16 per building instead of 5; they build in order, charged once each |
| 8 | **Windowed, audible, one-click launch** | desktop shortcut, no Battle.net, save games and settings untouched |

Numbers 1-5 came from earlier tasks; 6 and 7 landed last night.

## Under the hood (not gameplay, but they are why the above is trustworthy)

- The command card can now be read out of the running game -- which slot, which ability, enabled or greyed. That is how the Ghost cloak question was answered.
- Tests no longer steal your focus. Nine test suites drive the game in the background while you work.
- Nine automated in-game suites, plus offline checks, run before anything merges.

## Running now -- two tasks in parallel, as you said

**028 -- prove cancel/refund in a real game.** Answering your question from this morning. The risky half is cancelling an item OUR plugin holds, since that is the only place the plugin ever writes to your resources, and it has never been exercised in a running game.

**029 -- queue upgrades.** Just cut. This one I have deliberately told to send me a DESIGN before writing any code, and to watch the engine`s command stream FIRST -- because that is exactly the trap the >5 unit queue fell into: its first design handled a command the game never sends, every offline test passed, and the feature did nothing. Upgrades spend minerals AND gas, so I want the plan before the build.

They share the machine and will queue behind each other for game time. Neither steals your focus.

## Left after those

The wider screen (remastered-style viewport, stock HUD). That one is a renderer investigation and I would rather start it when nothing else is competing for the game.
