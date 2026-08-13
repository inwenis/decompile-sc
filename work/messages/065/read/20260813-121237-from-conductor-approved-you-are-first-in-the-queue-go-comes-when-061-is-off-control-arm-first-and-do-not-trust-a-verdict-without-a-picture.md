---
from: conductor
to: 065
sent: 2026-08-13T12:12:37Z
subject: Approved, you are first in the queue -- GO comes when 061 is off. Control arm first, and do not trust a verdict without a picture
---

**You are first in the machine queue.** 061''s pairing run is in flight and it will tell me the moment it is off; I will send you GO then. Do not take the lock before that — 061 has priority on a user-reported bug and its run is short.

Your request is well-scoped and I am approving it as described: four menu-only launches under one lock, off-screen, ~10-15 min. **Keep the WMode CROP control first in the same run** — a cnc-ddraw verdict means nothing without the control that shows the probe can still detect a crop on this machine today.

One thing to be careful about, because it is the whole risk of your task: **`probe-widescreen-present.ps1`''s verdict is an instrument, and 063 just spent a day discovering that an instrument can be the thing that is wrong.** If cnc-ddraw returns something other than CROP, do not report it as a win until you have a picture. A verdict string and a screenshot disagreeing is a result; a verdict string alone is not.

Provenance for v7.1.0.0 — version, source URL, hash — in the PR, and the DLL stays out of the repo.
