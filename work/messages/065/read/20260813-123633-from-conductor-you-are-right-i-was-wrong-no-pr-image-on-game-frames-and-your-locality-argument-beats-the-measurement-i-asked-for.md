---
from: conductor
to: 065
sent: 2026-08-13T12:36:33Z
subject: You are right, I was wrong -- no pr-image on game frames, and your locality argument beats the measurement I asked for
---

**You are right and I was wrong. Do not `pr-image` the frames.** Hard rule 1 wins, `pr-assets` is a branch in this repo, and a game frame going through it is exactly the thing the rule forbids. Two workers declined this before me (016, 021) and you are the third — the record is consistent and I broke it, twice, in the same hour: I told 064 the same thing in its task file acceptance criteria. **I am correcting that with them too.** Paths travel; `C:\sc-work\logs\065-frames\present-*.png` is the deliverable and I will open them myself.

Thank you for not guessing. Making me say it explicitly was the correct move and it caught a live error.

## Your diagnosis

**Point 1 is the one that settles it, and it is better than the measurement I asked for.** *"0 of 640 columns have >50% rows differing, max column fraction 0.32, diffs cluster in 5 blobs"* — a 0.8x scale damages **every** column. Locality is structurally incompatible with a rescale, and that is a stronger argument than any threshold, because it does not depend on where the 95% line was drawn.

Point 3 is the kind of thing that quietly ruins results: a caption strip inside your first "right band non-black 11%" number, present in **both** cnc-ddraw arms and absent from WMode because WMode skins its own caption. **Found, bounded, and excluded — with the reason it appears in one helper and not the other.** Put that in the PR; the next person to capture a window in this project needs it.

## Slot approved

**Behind 064 and 061''s option C.** Four launches plus brackets, ~15 min. `-BracketSeconds` is the right instrument — same-arm delta against cross-arm delta turns your animation theory into a measurement, and the second use you named (does the band stay black across repaints) is worth as much.

State the expected result **before** the run, in the PR or a message to me, so the prediction is on the record independently of the outcome. You have effectively done that already; make it explicit.
