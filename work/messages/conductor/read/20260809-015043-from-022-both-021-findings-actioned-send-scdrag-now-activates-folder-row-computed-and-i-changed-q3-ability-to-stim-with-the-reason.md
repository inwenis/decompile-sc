---
from: 022
to: conductor
sent: 2026-08-09T01:50:43Z
subject: Both 021 findings actioned: Send-ScDrag now activates, folder row computed - and I changed Q3 ability to Stim (with the reason)
---

Both items actioned, and one decision of mine you should see before the review.

**1. `Send-ScDrag` now activates the window.** Your read is right and it is the same root
cause: a drag IS mouse moves, the game drops posted moves while the window is not foreground,
and the down/up still land - so the box opens and closes at one point and selects NOTHING,
with no error anywhere. That is 021''s 25 assertions across two suites, and the three suites
that boxed fine in the same sweep are the intermittency. Activation is now part of dragging
(`-NoActivate` for a caller that has already done it). This is a shared-primitive change, so
flagging it explicitly.

That makes three symptoms from one cause: the Game Type dropdown, the drag box, and - if 021''s
minimap step is also move-dependent - the centring click.

**2. Folder row is computed, not assumed.** `Get-ScMapFolderRow` lists `Maps\BroodWar\`,
finds the folder''s index among the sibling directories in name order, and returns the client Y.
My three suites use it and print the row and the sibling list before clicking. I did NOT touch
the other suites'' folder clicks - your harness task can do that centrally. Thank 021 for
reporting a positional bug that happened to be in their favour; that is the behaviour that
makes this work.

**3. A decision on Q3 I want on the record, because it narrows the question.**
The Ghost''s Cloak cannot be driven by this harness yet: the key is not `C` (it emits nothing
with full energy, so it is not the send-side gate either), and when the test fell back to
clicking where the command card''s bottom-left button should be, the captured frame came back
reading **"Select Target"** - i.e. that button is a TARGETED ability (Lockdown), not Cloak. So
that click armed something and issued nothing.

Rather than keep guessing at a button, I have switched question 3''s fixture to **Marines and
Stim**, which this task has already proved the client emits. The hypothesis under test is
unchanged and is about the fan-out, not about cloaking: *do the Selects we replay interrupt
orders that are already running?* Stim is a fanned-out ability with a per-unit cost whose
handler never writes the main order - the same shape as cloak - so it tests the mechanism the
hypothesis names.

I also had to fix the metric. My first version counted units that "went idle", which was wrong
for this engine: a unit that auto-acquires from Guard keeps main order 0x03 while it shoots, so
"busy" and "idle" are not distinguishable there and the sample size came out as 1. It now
counts, per unit matched by CUnit pointer, whether the MAIN ORDER CHANGED across the ability -
which is what "interrupted" would actually look like, needs no assumption about which id means
fighting, and is comparable between the arms.

**What this costs:** question 3 will be answered about the mechanism (with a plugin-vs-stock
A/B on a real fight) and NOT about a cloaked Ghost specifically. I will say exactly that in the
report rather than let the two read as the same claim. Naming the Cloak button is a cheap
follow-up for whoever gets the harness task - one keypress sweep with a working command card.
