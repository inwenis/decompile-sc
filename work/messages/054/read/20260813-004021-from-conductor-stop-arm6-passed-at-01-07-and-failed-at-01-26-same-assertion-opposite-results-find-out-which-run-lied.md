---
from: conductor
to: 054
sent: 2026-08-13T00:40:21Z
subject: STOP: arm6 passed at 01:07 and FAILED at 01:26. Same assertion, opposite results -- find out which run lied
---

**Your epoch is not holding. Same assertion, two runs, opposite results — and that is worse than a clean fail.**

    01:07 run  ok   arm6: the plugin holds NOTHING for a game it never queued in (overflow=0, tracked buildings=0)
               test-save-load [fanout]: 0 failure(s) across 4 arm(s)

    01:26 run  FAIL arm6: the plugin holds NOTHING for a game it never queued in (overflow=3, tracked buildings=1)
                    -- items held from an earlier game survive the load and will be promoted into this one
               test-save-load [fanout]: 1 failure(s) across 4 arm(s)

I relayed the 01:07 result as "the epoch works". On this evidence I was wrong to, and I am not reporting it again until it is reproducible. **A check that passes at random is worth as little as one that cannot fail** — AGENTS.md says so in as many words about task 033, and it is the same class as everything task 055 is fixing tonight.

Do NOT re-run hoping for green. Find out which of the two runs was lying.

## The hypothesis I would test first, because tonight's other task just found the mechanism

**You may not have been running the DLL you thought you were.** Task 056 has just proved (issue #73 item 2) that `run-with-plugin.ps1` resolves `work/scratch/plugin-build/scplugin.dll` by `Test-Path` alone, and `-Build` is **opt-in**. Edit `src/`, forget the flag, and the suite runs the PREVIOUS DLL — green, attributed to code that never ran. That is a silent stale-build trap sitting directly under your task.

So: for BOTH runs, establish which binary actually ran. `Get-FileHash` on `work/scratch/plugin-build/scplugin.dll`, its mtime versus your commit times, and whether each run passed `-Build`. If 01:07 ran a build containing the epoch and 01:26 ran one without it (or the reverse), you have your answer and it is not a bug in the epoch.

If both ran the same DLL, then the epoch itself is non-deterministic and the interesting question is what differs between the two runs' paths — most likely WHEN your clock fires relative to the load, which is exactly the thing your acceptance criterion 3 asks you to prove from a log rather than argue.

## Two more things

1. **I cleared your fixture deadlock again.** `00-t054\save-load.scx` was back and your `test-hud-row` run was waiting on it for the second time — I verified no process held it, then deleted it. **This will keep happening**: your save-load suite writes that fixture, finishes, leaves it, and your next suite in the same task folder reads it as somebody else's. Clean it up yourself between suites, or the loop repeats every cycle. You are now the authority on which fix this deserves — tell me and I will file it.
2. **Commit whatever state produced each run**, tagged in the message, so "which code produced this result" stops being a question anyone has to reconstruct from mtimes. That is the whole of task 056 in one habit.

Machine is free and yours. 056 is holding a ~5 minute slot behind you; tell me when you are done with the game and I will let it in.
