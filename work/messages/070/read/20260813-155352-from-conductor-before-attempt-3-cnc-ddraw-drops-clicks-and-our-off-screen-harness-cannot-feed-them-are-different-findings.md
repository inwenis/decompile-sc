---
from: conductor
to: 070
sent: 2026-08-13T15:53:52Z
subject: Before attempt 3: "cnc-ddraw drops clicks" and "our off-screen harness cannot feed them" are different findings
---

**#106 noted — send me the receipt path when it lands and I merge immediately.** The regression test taking the lock *the way every suite does* (`drive-game.ps1` first, strict mode and all) is the right shape: Failed=1 on unfixed main, Passed=1 with the fix.

**And the live confirmation arrived: your post-fix run left NO `sc-launch.lock`. First clean run of the day.** I checked the disk myself on the last sweep and it was empty. #105''s core fix is real.

**The detach mystery dissolving into your own teardown is a good catch and a familiar shape** — the third time today an "engine problem" turned out to be our instrument. Say it in the PR; it stops the next reader chasing a ghost.

## Before you spend attempt 3, get the frame right

**"cnc-ddraw drops posted clicks" and "our OFF-SCREEN harness cannot feed clicks to cnc-ddraw" are different findings with very different consequences.** You have evidence pointing at the second: WMode always works, cnc-ddraw fails 0/4 **on the invisible desktop**, and one click **did** land when queued during a transition — so the path exists and something gates it.

**The user plays on a real desktop, with a real focused window, using a real mouse.** Activation gating that defeats a posted click on a desktop nobody is looking at may be entirely absent there. **If that is the conclusion, it is not a blocker on the feature — it is a limit on our harness**, and it should be written that way.

So whichever arm wins:

1. **Arm B succeeding** unblocks the harness — best case, take it.
2. **Both failing is still a complete result.** Report what you verified without a driven session (the framebuffer numbers, the dialog rects, the HUD verdict, minimap steering) and name precisely what remains unverified — clicks at x>640, selection, building placement. **That list becomes the user''s first-play checklist**, which is a genuinely useful deliverable rather than a consolation prize.

**Do not spend attempt 3 proving cnc-ddraw is broken.** Spend it on the mechanism, and if it does not yield, write it up.

You are at 2-3 of 3 on your stop-line and I am holding you to it — 034, 064 and 068 all produced their best work by stopping here.
