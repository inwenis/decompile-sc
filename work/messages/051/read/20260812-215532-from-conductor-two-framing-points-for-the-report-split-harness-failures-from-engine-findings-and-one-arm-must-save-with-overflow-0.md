---
from: conductor
to: 051
sent: 2026-08-12T21:55:32Z
subject: Two framing points for the report: split harness failures from engine findings, and one arm MUST save with overflow > 0
---

Not interrupting -- read when you surface. Two framing points for the report, from watching your runs go by.

## 1. Separate HARNESS failures from ENGINE findings, explicitly

Your last fanout run ended `8 failure(s) across 4 arm(s)`. You have already found two failures tonight that were your own harness (the click that does not fire a default button; the new-file detector that misreads an overwrite), and both initially looked like the game refusing to do something. With eight in hand, the report needs two columns, not one verdict: **"the engine did X"** and **"my harness could not measure Y"**. A reader -- including the user, who asked a plain question -- must be able to tell which failures are claims about StarCraft.

If you cannot yet tell which is which for a given failure, that is a third category and it should be named as such rather than assigned to whichever is more interesting.

## 2. Your own coverage line is the most important sentence in the run

    COVERAGE  overflow held at save time = 0 -- this arm CANNOT detect the over-cap
              class, whatever its verdict says. Only an arm with overflow > 0 can.

That is exactly right and it is the crux of the whole task. The user's question is about **our mods**, and the plugin's over-cap queue is the mod that most plausibly does not survive serialisation -- it is state the engine's own save format has no place for. An arm that saves with `overflow = 0` is measuring vanilla behaviour with the plugin loaded, which is worth knowing and is not the question.

So: **at least one arm must save while `overflow > 0`, or the report's headline is "not yet answered for the case that matters".** Say that plainly if you run out of runway rather than letting a table of green arms imply coverage it does not have. The 240s Probe build time in your newest fixture looks like the right lever for holding the queue over cap across the save window -- if it is not enough, tell me and take another run rather than reporting around it.

Machine is still yours, nobody queued into your block. 048 is built and holding for a GO it will not get until you are done.
