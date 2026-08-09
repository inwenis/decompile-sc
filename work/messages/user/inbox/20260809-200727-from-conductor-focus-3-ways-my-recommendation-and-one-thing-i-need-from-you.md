---
from: conductor
to: user
sent: 2026-08-09T20:07:27Z
subject: focus: 3 ways, my recommendation, and one thing I need from you
type: question
options: machine is free now - release the 3 blocked workers; wait for the permanent fix (027), do not run tonight; build a VM for game tests
---

Three ways to handle this, cheapest first, with my honest read:

**1. The permanent fix, already being built (task 027).** Run the game so it never comes to the front over your work — either share input with it without raising its window, or put it on its own hidden Windows desktop while you work on yours. Same machine, no VM, no scheduling, and it makes EVERY future test invisible to you, not just tonight''s. If it works — and the first thing 027 is testing is nearly free — this is strictly better than the other two. This is what I would spend the effort on.

**2. Run at night when you''re away.** Zero engineering, and it is a fine STOPGAP — but it does not scale (every future in-game test waits for a window when you''re gone), and it breaks the moment you sit down at 1am. Good for tonight, not a real answer.

**3. A VM.** Real isolation, tests run anytime. But it is the heaviest option: a Windows VM, and StarCraft 1.16.1 is a DirectDraw game from 1998 — VMs are hit-or-miss with its graphics, and our whole worker/injection machinery would have to reach into the VM or run inside it. I''d only build this if option 1 proves it genuinely cannot hide the window. Solid Plan B, wrong Plan A.

**My recommendation:** let task 027 land the in-process fix (option 1) as the permanent answer — do NOT build a VM yet. AND, since you''ve offered the machine: use tonight as the immediate unblock. Three features are finished except their in-game verification and are sitting idle only because of focus-stealing — building selection, queue-more-than-5, and the cloaked-ghost investigation. If you tell me the machine is free now, I release all three, they run their tests back-to-back (they take turns automatically — no collisions), and you get three more merged features by morning instead of waiting on 027.

**So the one thing I need:** is the machine free right now for a burst of test runs? Pick a button. "Release now" finishes three features tonight; "wait for 027" holds until the invisible-launch fix lands; "build a VM" if you''d rather I invest in that isolation. My vote is release now — it costs you nothing but the machine for a while, and 027 still lands the permanent fix regardless.
