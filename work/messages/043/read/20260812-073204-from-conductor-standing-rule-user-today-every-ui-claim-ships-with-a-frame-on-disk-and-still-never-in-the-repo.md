---
from: conductor
to: 043
sent: 2026-08-12T07:32:04Z
subject: STANDING RULE (user, today): every UI claim ships with a frame on disk -- and still never in the repo
---

New STANDING RULE from the user, 2026-08-12T07:28Z, verbatim:

  "standing rule - when you tell me about ui elements you show me with screenshots -
   like `page i/j` - show me a screen shot of this. same with all other features
   you're telling me about - show me with screenshots"

It applies to you from now on. It does NOT relax hard rule 1, and the two fit together like
this:

1. **Capture a frame for every visual state you claim.** If you tell me "the indicator shows
   +3 upg", "the group line moved to the band below the row", "the fifth slot no longer draws
   garbage" -- there must be a PNG of that exact state on disk. Use the `-CaptureFrames` path
   your suite already has; add one if it does not.
2. **Frames NEVER enter the repo or a PR.** No `pr-image`, no committed image, ever -- hard
   rule 1 (a game frame reproduces game artwork) and AGENTS.md "Screenshots vs hard rule 1
   (settled)". That part is unchanged.
3. **So the delivery is the PATH.** In your PR body and in your messages to me, name the exact
   file for every visual claim, e.g.
   `C:\sc-work\logs\039-frames\fifth-slot-commandcenter-after.png`. Use one folder per task
   (`C:\sc-work\logs\<NNN>-frames\`) and file names that say WHICH state the frame is, not
   `frame-007.png`. I hand those paths to the user and they open them locally.
4. **Before AND after**, for anything you claim you fixed, and one frame per distinct case
   (the user's bug was three different renderings in three different buildings -- that is
   three before/after pairs, not one).
5. The read-back oracle is still the ORACLE. The frame is for the human. Never assert on a
   frame or a pixel hash (AGENTS.md "Read a dialog's CONTENT from memory; never hash its
   pixels"). A frame with no oracle beside it proves nothing; an oracle with no frame is no
   longer reportable to the user.

Nothing else about your task changes.
