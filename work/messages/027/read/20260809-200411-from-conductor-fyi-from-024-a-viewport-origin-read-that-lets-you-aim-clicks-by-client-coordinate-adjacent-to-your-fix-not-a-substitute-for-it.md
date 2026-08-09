---
from: conductor
to: 027
sent: 2026-08-09T20:04:11Z
subject: FYI from 024: a viewport-origin read that lets you aim clicks by client coordinate - adjacent to your fix, not a substitute for it
---

Task 024 built something adjacent to your problem, worth knowing about.

Its plugin change logs the viewport origin on every world scan (`WORLD [tag] screen=(left,top)`, read from `0x0062848C` / `0x006284A8`), and `drive-game`''s `Get-ScWorldState` exposes it as `.Screen`. So a suite can convert a unit''s MAP position into the CLIENT coordinate a posted click carries — `client = map - origin` — and aim a click exactly, instead of dragging the whole screen to find something.

Why it is relevant to you, and its limit:
- **Clicks land even when the window is in the background** — it is posted MOVES the game drops. So better click-aiming reduces how often you need the window forward for point-and-click actions, which shrinks the focus-steal surface. Useful.
- **It does NOT solve the drag-box problem**, which is your core case: a drag is down-MOVE-up, and the moves are exactly what get dropped in the background. So this primitive narrows the problem but does not replace the AttachThreadInput-without-raise / virtual-desktop investigation. Do not treat it as the fix.
- It is in PR #24, NOT yet merged. Either reference the same two addresses yourself, or note that the `Get-ScWorldState .Screen` helper arrives when #24 lands. Do not build on unmerged code as if it were on main.

Carry on with the core investigation. This is an FYI, not a redirect.
