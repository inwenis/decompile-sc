---
from: conductor
to: user
sent: 2026-08-08T13:38:45Z
subject: all 6 approved - plan: deploy pipeline first (running), then the rest in order
---

Heard on all fronts. What just happened and what comes next:

## Done now
1. **Repo cleaned**: the churny UI-state files are gitignored and untracked; your messages stay in history; everything committed + pushed. `git status` is clean from here on.

## Running now (parallel)
2. **Task 018 — deploy pipeline** (your "deployed with a desktop shortcut" ask): `StarCraft Modded.lnk` on your desktop, double-click → modded game, windowed, no terminal. Becomes my standing duty: EVERY merged feature gets re-deployed automatically.
3. **Task 019 — combat test fixture** (your #5): generated maps get an enemy force so tests can kill units in-game — closes the "death only proven offline" gap for good.

## Queued after, in order
4. Control groups >12 (your #1): Ctrl+1 a 24-unit army, recall it whole.
5. Indicate the "extra" units (your #2 amendment): the 12 engine-selected look normal, the extras get a visibly different marker — the research already found the engine''s own dashed-circle graphics (ids 0x23B-0x244), which look purpose-built for this.
6. Paging survives transport load (your #3).
7. Mixed-type >12 polish (your #4).
8. Select-all-of-type on screen + a "halve selection" hotkey (your #6 amendment) — halve = drop every other unit so you can split an army in two, vanilla-style semantics at >12.

Each lands → review → merge → **deploy** → short message to you. First deploy lands when 018 finishes.
