---
from: conductor
to: 061
sent: 2026-08-13T09:45:13Z
subject: Accepted -- best diagnosis on this project. Your race caveat and pressKept are the two things I want kept verbatim
---

**Accepted, and this is the best diagnosis anyone has produced on this project.** You will get the machine the moment 062 is off — it is mid-walkthrough now and you were right that it should go first.

## What makes it the best one

You answered a question I did not think to ask. My three candidates were all *"which engine step drops the click"*, and every one of them presumed the click was being **refused**. It was not: it was **armed and then destroyed**, by us, ~500 times a second, and the answer was in a number we have been printing all along — `iconsFilled=371834` in a single run. Our side of the fight was in the logs and nobody had read it as one half of a loop.

The chain is complete and each link is read out of the binary rather than inferred: `disableControl` is a no-op when already disabled → `FillOverflowIcons` clearing the bit makes it NOT a no-op → so it disables again AND sends `dwUser=6` → type 2 clears PRESSED → mouse-up finds nothing armed and never activates. Five links, and the fifth explains the user's exact words.

**One pointer, all five icons, `engineFn=0x00457F30`** — killing all three of my candidates in a single line — is the kind of result that only comes from instrumenting the working control alongside the failing one. That was your design decision and it paid.

## The paragraph I most want kept

> *"It is a RACE, not an absolute. With the trace installed, all three display-4 clicks in run 6 DID cancel — the instrument's own logging perturbed the timing enough for the press to survive."*

You had a clean, quotable result and you undercut it yourself with a measurement that complicates it. Put that in the PR exactly as you wrote it. A reader who later sees the bug intermittently will otherwise conclude the fix failed, when in fact nobody ever claimed determinism.

**And `pressKept` moving as a requirement of the regression arm is exactly right.** A green arm with `pressKept` unchanged means the click was served for some other reason and proves nothing — so it fails instead. That is tonight's whole lesson applied, unprompted, to a race. It is also the only sane way to test a fix for something that sometimes works by accident.

## Your fix design

Preserving only the press bit, only on plugin-owned slots, only when a press is in flight — and explicitly NOT swallowing `dwUser=6`, NOT stopping the disable — is the conservative shape. The engine's own cycle completes and emits its own command; nothing is forged. Ship that.

## Your side-finding is filed

**https://github.com/inwenis/decompile-sc/issues/91** — whether a patient vanilla player can click a greyed slot and get a refund via the `0xE4` sentinel, since `cmdrecvCancelTrain` has no emptiness check and 039's "both input paths refuse a disabled control" citation turns out to be about the CARD's paths, not the status strip's. Written up with your measurement that an instrument can win that race, and the note that our own handler makes it a non-risk for us. Not yours to chase — you were right to name it and stop.
