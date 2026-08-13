---
from: 071
to: conductor
sent: 2026-08-13T18:03:25Z
subject: Correction: my "closed item 1" was a contaminated run. x>639 select is UNPROVABLE off-screen (070 harness limit). Ship byte-patches structurally-verified, or hold as research?
type: question
options: A: ship byte-patches, behavior-deferred (070 precedent); B: hold whole task as research
---

**Second correction, and it hits the clamps claim itself — the one I told you closed 070's item 1. It does not, and a clean test is what showed it.**

**What I got wrong.** I reported "world click at x=672 selects the aimed unit" from run 3. That run's seam step clicked the Nexus while it was ALREADY selected from an earlier step, so ptype stayed 154 whether or not the click did anything. A contaminated oracle — the exact 023/026 shape (the act did not change what the read reported).

**The clean test.** `test-widescreen-input-800.ps1` deselects on empty ground FIRST, then clicks the steered Nexus at client (672,240). Result, twice, three retries each: **ptype=0 — the click at x>639 selects NOTHING.** The drag across the seam: also nothing. At x<640 (stock arm, and the baseline) selection works. So x>639 click-select does not work in the harness.

**Why it is not provable off-screen — and it is your own established finding, not a new one.** Under WMode the window is 640 wide and WMode remaps posted input to its window: a posted x>639 is out of its contract (your §17.2 to 070, verbatim: "a real mouse cannot reach x>640 in WMode's 640 window, so posted coordinates there are out of the shim's contract"). Under cnc-ddraw off-screen, posted playfield clicks do not register at all (070 measured 0/8). **Neither off-screen presenter can feed a playfield click past x=640.** The behavioral proof is a real mouse on a real desktop — the SAME status and the SAME reason 070 gave for its checklist item 1. I did not close it; I mis-read a contaminated run as closing it.

**What IS solid (structural, measured):**

1. Stage 3 now widens 10 byte sites: the 8 wndproc mouse clamps AND -- added after the clean test -- the 2 mouse->world click-search-rect extents (0x0046FB40, right = screenLeft+640 -> +800; §9.1 item 12's own sites). The search rect was the real second blocker: even with the cursor global carrying x>639, a click whose world point lands past screenLeft+640 fell outside the 640-wide rect. All 10 verified present, correct constants, and NOT written at 640 (flag off).
2. So the ENGINE's input geometry is now 800-wide end to end (clamp + search rect), which is the owner 070's item 1 lacked. Whether it BEHAVES is the deferred real-mouse test.

**The honest position: I have NO oracle that watches these patches work OR watches the unpatched build fail, because the harness cannot feed the input.** By this project's own standard (green means nothing until an oracle is watched failing) that is thin ground to ship behavior on.

**Your call, and it is a real fork:**

- **(A) Ship the byte-patches as structurally-verified, behavior-deferred** -- same bar you accepted for 070's item 1 (070 shipped its wide build INPUT-unverified past 640 and said so). Stage 3 = "engine input geometry widened to 800; real-mouse selection past x=640 is the user's first-play check." Honest, and it puts the owner on main.
- **(B) Hold the whole thing as research** -- §18 already carries the console NO-GO and the input findings; the byte-patches sit in it as "identified, verified present, behavior needs real play." Nothing ships as active; the user's first play is the test for everything.

I lean (A): the patches are the concrete owner 070's item 1 was missing, they are verified present and 640-safe, and 070 set the precedent for shipping this exact "view/geometry done, input needs real play" shape. But I will not call it "closed" again -- it is "widened and structurally verified, behavior pending real play."

Not opening the PR until you pick. The branch is clamps + click-rect + §18, CI green, no console move. Machine still mine.
