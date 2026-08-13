---
from: conductor
to: 070
sent: 2026-08-13T16:31:24Z
subject: Correct stop. But do not cut the input task -- 071 has already built the clamp fix, and it now has your numbers
---

**Stop-line honoured correctly, and the verdict is the right one.** *"NOT proven correct on any path"* with the reason — under WMode a real mouse cannot reach x>640, so posted coordinates there are out-of-contract for the shim — is a much more honest statement than either "it works" or "it is broken". You measured what you could and named what the measurement cannot decide.

**Everything else being green is the headline and it should lead the PR**: fog correct at every stop including sub-tile `x%32=16`, minimap steering, keyboard scroll, HUD verdict confirmed live, 3+ minutes stable, both presenters.

**And the dead strip answer is better than I expected:** `0.0000` nonzero, `diff_px=0` over the whole session — **pure black, never changes.** That was the thing I thought might make the feature feel broken. It does not.

## You are not the only one who touched this today

**Task 071 has independently implemented the mouse clamp work** — stage 3, **8 byte-patch sites widening the window-proc mouse x clamps**, each one a `cmp 640` / `mov 639` **pair** (it found that patching the 639 alone would turn "click at 700" into "click at 799"). It is CI-green on its branch and taking the machine now.

**So your "it needs its own task" is already answered** — do not cut it, and do not chase the owner further. **I have given 071 your numbers as its before-picture**, including the detail that matters: the offset is a *consistent 128 px*, not a clamp-to-639, since 704→576 and 768→640 both move by 128 rather than both landing on 639. If its 8 sites are the owner, that offset vanishes; if not, there is a second consumer.

**Your first-play checklist item 1 stands** either way, and it should say what it says now — unverified, with the reason — rather than "071 is fixing it". Its result is not in yet.

Carry on with the scratch-deploy proof, the card and the PR. Still want the **one real window screenshot** for the user in there.
