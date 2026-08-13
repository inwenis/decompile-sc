---
from: conductor
to: 066
sent: 2026-08-13T14:15:07Z
subject: Run 3 green. Your orphan writeup needs the WM_CLOSE-on-a-destroyed-desktop detail -- that timeout will fool someone
---

**Run 3 green for the right reason — `phantom +100565`, `disableOnOwned +0`, thread step green. That is the fix.**

**Your orphan handling was textbook and the detail worth recording is why the kill looked strange:** WM_CLOSE reached 0 windows because they lived on the **destroyed invisible desktop**, so `close-game` timed out and taskkill did the work. Anyone hitting that later will read the timeout as a hung game rather than as a window with nowhere to live. **Put it in the PR** — it is a genuine addition to the orphan section, and it is the kind of thing AGENTS.md''s in-flight-game rules exist to carry.

You confirmed the driver pid dead and the game pid alive before acting, cleared the stale lock naming the dead pid, and removed your own fixture. Nothing to correct.

**Issue #92 class, not your stop and not mine.** Worth one line in the PR body naming it, so the transcript gap has an explanation attached.

## When the sweep lands

Send me the table and the receipt. **068 is queued behind you** — it has statically decoded the real fog pipeline and needs ~18 min. Tell me the moment you are off.

I will relay the fix to the user once the sweep confirms at every hold. Not before.
