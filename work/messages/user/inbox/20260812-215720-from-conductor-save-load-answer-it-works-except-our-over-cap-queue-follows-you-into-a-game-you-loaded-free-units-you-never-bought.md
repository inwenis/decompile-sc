---
from: conductor
to: user
sent: 2026-08-12T21:57:20Z
subject: Save/load answer: it works, except our over-cap queue follows you into a game you loaded -- free units you never bought
---

**Your question is answered, and the answer is: saving and loading works, except for one thing our mod does — and that one thing is a real bug you can hit in normal play.**

Not final yet; one arm is still running. But the finding is solid and you should know it tonight, because it affects how you play tomorrow.

## The short version

Saving and loading a game with the plugin active works. The engine restores its own world correctly — unit counts, types, positions, hit points, the production queue's contents, your minerals. All verified against the engine's own arrays, on a plain no-plugin control first and then with the plugin in the mode your shortcut uses.

**But the plugin's over-cap queue does not belong to the game you saved. It follows you.**

## The bug, in your terms

1. Queue more than 5 units at a building. The extra ones are held by our plugin, not by the game — that is the whole feature, and you paid minerals for them.
2. Load any earlier save. Even a save made in a different game, made before the plugin existed, with no queue of its own.
3. The plugin walks into that loaded game **still holding the extra items from the old one.**

Measured: a game whose save file contains a queue of four and no overflow at all was loaded into a session that had earlier queued 8 at a building in a *different* game. The engine's own array came back perfectly correct. The plugin arrived holding three Probes from the game that no longer exists — paid for there, not here.

Nothing visible happens straight away, because the building's queue is full. The moment one unit finishes and a slot frees, the plugin promotes a phantom item into a building that never queued it. You get units you did not buy in this game.

## Why it happens

The engine restores buildings into a fixed table, in place — the same memory address before and after the load. The plugin's check for "is the building I am holding items for still alive?" asks whether the unit at that address is still the same unit: same id, same owner, same hit points. A load restores all three verbatim, so a stale record looks perfectly alive. The check cannot tell "still there" from "restored into the same slot by a different game".

## What I am doing

Not fixing it inside the task that found it — an investigation that starts fixing things stops being trustworthy about what it measured. 051 is writing it up as an issue precise enough to cut a fix task from, and that fix is the next thing I will dispatch.

**Until then, if you want to be safe: after loading a save, quit to the menu and relaunch before queuing over the cap again.** A fresh process holds nothing.

## Two things worth noticing about how this was found

The suite's first control run **passed all nine of its round-trip checks without a load ever having happened.** Everything it compared matches when the two states are the same — and a load that never occurred produces exactly that match, because the game just carries on. 051 caught that itself and added a witness: queue one unit at a second building after the save, then require the load to have erased it. If the witness survives, the run reports INCONCLUSIVE rather than passing.

And the assertion that was supposed to catch tonight's bug **passed** — it compared the engine's ring, which is the half that is correct. The bug lives in the half nobody was looking at.

Also filed: [#62](https://github.com/inwenis/decompile-sc/issues/62), a smaller oddity found on the way — a mouse click fires three of the game's dialog buttons and silently does nothing on the fourth. 051 nailed down what it is *not* (not the button type, not the default flag) and refused to declare what it *is* on one example, which was the right call.
