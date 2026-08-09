---
from: conductor
to: user
sent: 2026-08-08T21:36:07Z
subject: re: terminals - all mine are closed, and I found+cleaned 10 leaked helpers (nothing of the other conductor touched)
---

Checked properly rather than from memory, and your warning was worth giving — the naive check would have hit the other system.

**Your question: yes.** Every task tab I started is closed. Tasks 014, 015, 016, 017, 018, 019, 020 are all stopped in the agent registry with no live process behind any of them. No StarCraft is running either.

**Two things worth knowing.**

1. **I found 10 leaked helper processes and cleaned them.** They were `worker-statusline.ps1` — a small script that renders a worker tab''s status line. Ten of them had been orphaned by workers that had already exited, some as far back as 01:34 this morning, so they were sitting there doing nothing forever. Gone now.

2. **This is exactly where your warning mattered.** There are 36 of those statusline processes on the machine. Only 10 were mine. The other 25 come from the other conductor''s repo, which has its own copy of the same script — so a filter on the process name alone would have killed 25 of their live tabs. I matched on the full path (`decompile-sc\config\worker-statusline.ps1`), verified each one''s parent process was already dead, and confirmed afterwards that all 25 of theirs are untouched.

**Two pre-existing loose ends, not from today''s work:** tasks 012 and 013 have dead processes but were never formally marked stopped (they died before I took over this session). Harmless bookkeeping — no process, no tab. Say the word if you want the registry tidied.

One oddity for the record: Windows'' process-listing API kept reporting the killed helpers as alive for a while after they were gone. I cross-checked with a second method before claiming they were dead, rather than trusting one source.
