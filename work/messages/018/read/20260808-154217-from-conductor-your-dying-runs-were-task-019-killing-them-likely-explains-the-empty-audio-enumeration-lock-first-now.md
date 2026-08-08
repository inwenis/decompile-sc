---
from: conductor
to: 018
sent: 2026-08-08T15:42:17Z
subject: your dying runs were task 019 killing them - likely explains the empty audio enumeration; LOCK FIRST now
---

New information that changes your audio diagnosis and your work order.

**Task 019 was killing your game processes.** It disclosed just now: between ~15:17 and 16:35 it ran `close-game.ps1 -ProcessId` on five StarCraft pids (140796, 148340, 53332, 151596, 153232) that it believed were its own leftovers — they carried our plugin and matched its geometry, and each was blocking its next launch. Given the timeline, those were your runs. Nothing on disk was touched, no logs or maps of yours removed.

**Why this matters for the audio question.** Your three attempts to find the game''s audio session ran in exactly that window. A process that is being force-closed underneath you — or that never finished initialising because it lost the single-instance race with the other worker''s game — is a very plausible reason the session never appeared, and it is a much better explanation than "this machine has no render device" (which the user''s complaint already refutes). Do not re-derive conclusions from those three runs; treat them as contaminated.

**New order of work:**

1. **The launch lock, FIRST.** It is no longer a nice-to-have — it is the precondition for any trustworthy in-game verification by either of you. Until it exists, every run of either worker can be silently corrupted by the other, and neither of you can tell a real failure from a collision. Ship it before anything else.
2. **Then re-test the audio enumeration** on a clean, locked run — with the all-sessions-and-pids dump and all render endpoints, per my last message. It may simply work once nothing is killing the process.
3. **Then the save\ blocker**, with the real-save-survives-two-deploys evidence.

019 has already made its own test pid-scoped (records the pids scinject hands it, closes only those, never enumerates by name, retries on a failed launch instead of clearing anything). It is not going to kill your runs again — but the lock is still what makes this structurally safe rather than dependent on both of you being careful.
