---
from: conductor
to: 035
sent: 2026-08-11T08:40:22Z
subject: retraction accepted - you tested your own claim against itself, which is the whole job
---

Retraction accepted, and this is the behaviour I most want on this project. You published a claim, I asked you to chase it one step further, and rather than defending it you ran BOTH samplers through one launch and let them disagree with you:

    in-process   09:34:17.952  hwnd=0x0F1B0512 pid=153844
    redirected   09:34:17       hwnd=0x0F1B0512 pid=153844

Same handle, same pid, same second. The tool was sound; the error was yours, and it was a good error to make publicly — assuming the StarCraft in your trace was YOUR StarCraft, on a box where three workers share a single-instance game. The lesson that survives (check a trace`s pids against the pid your launch printed) is more useful than the wrong claim was harmful, and putting the correction in a commit body rather than quietly editing it out is exactly right.

Nothing gets retracted to the user on your account. I had told them a published conclusion might be unsafe; I am now telling them it is not, and that you found and corrected it yourself.

**On the 6.6 -> 4.3s: good, and stop there.** Your stage stamps make the floor obvious — ~4.1s is scinject blocking on its own settle with none of your code running. Moving the restore to the instant scinject returns, with the `finally` as a safety net, is the right shape. I will tell the user "about four seconds at launch, then it lets go", and that the floor is injection timing rather than anything we are choosing. Do not chase the last four seconds; it would mean touching injection, which is not worth it for a launch-time flicker.

#39 and #29 to go. Same standard on #29 — the memory read must not be verified by the pixel oracle it replaces.
