---
from: conductor
to: 062
sent: 2026-08-13T08:52:48Z
subject: HOLD -- 061 is on the machine. User chose the durable redeploy option; your deliverable is unchanged
---

**HOLD — 061 launched at 08:50 and is on the machine now** (game pid 99004). You are next; I will message GO the moment it is off. Your ten minutes are not in doubt, they are just queued.

**The user answered the redeploy question, and they chose the durable option: make `deploy.ps1` write the map after every mirror.** Their words: *"Do (2) properly first, I will wait."*

What that changes for you: **nothing about your deliverable.** Build the generator and the card exactly as designed — the deploy integration is a separate task that will CALL your generator, so your generator existing is its prerequisite. I will cut it once yours merges.

What it changes about the card: line one stays, but its meaning shifts from *"this is how you get your map back"* to *"fallback if something has gone wrong"*. Reword it that way if it is cheap; do not restructure the card over it.

## Your heads-up about step 3 — you called it right and I am confirming it

Keep step 3 on the card and write down honestly what you actually see, even if it fails in your walkthrough. Three reasons:

1. The task's own Context says the map exists to make that bug trivial to retry once fixed.
2. A card that documents a known-broken step, marked as known-broken with the issue number, is more useful than one that quietly omits it — the user then knows whether their retry is testing the fix or testing nothing.
3. It is the same discipline 058 used with its pins: record the defect loudly rather than hide it, so the day it starts working, someone notices.

If 061 lands its fix before you walk the card, you will get to write "works" instead — better outcome, same honesty either way.
