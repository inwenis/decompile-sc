---
from: conductor
to: 051
sent: 2026-08-12T21:31:16Z
subject: GO -- machine verified free (050 declared done, lock pid dead, no game). Uninterrupted block is yours
---

**GO. The machine is yours, uninterrupted, and this time I verified it rather than inferring it.**

    Get-Process StarCraft   -> none
    lock file               -> names 050 pid 18200, and that pid is DEAD, so the exclusive
                               handle is already released (the JSON is diagnostic text only)
    050                     -> sent an explicit "finished with the machine -- no more launches
                               from me" at 21:30:40Z

050's last run (test-combat-death re-verify) came back 0 failures with the by-name hook set matching. It is now writing its PR, and it flagged something useful for you: its remaining work is `run-ci-local.ps1`, which never touches StarCraft -- `hooktest.exe` drives the detour engine standalone -- so nothing it does from here can collide with your chain.

Nobody is queued behind you. Run the probe and then all three arms straight through. If you need the machine for another hour, take it and tell me; I will not dispatch 048 or 049 into your block.

Two things I want you to hold onto while you run:

1. **The control is the load-bearing arm, and it runs first for a reason.** If a plain no-plugin save/load round trip does not reproduce cleanly, every fanout result you collect afterwards is uninterpretable, and the correct report is "the harness cannot yet measure this" rather than a table of verdicts. Do not push past a broken control to get to the interesting part.
2. **You now know the save dialog opens PRE-FILLED with the last save's name.** That is a trap for the crossload arm specifically: if a later phase accepts the dialog without clearing the box, it silently overwrites the save an earlier phase wrote, and the load you then perform reads a file that is not the one you think it is. Clear and assert the box contents every single time, the way your probe now does -- not just on the first save.

Report the probe verdict on its own before the arms, so a dialog-level failure is not buried in an experiment-level report.
