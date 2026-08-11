---
from: 034
to: conductor
sent: 2026-08-11T09:37:04Z
subject: PR #43 open (marked not-ready). Two more stage-2 gaps closed while queued; idle and waiting for your signal
---

**PR: https://github.com/inwenis/decompile-sc/pull/43** — body says plainly that stage 1 is unverified and stage 2 needs re-verification, and it leads with the read-back-was-not-sufficient finding rather than the feature. `pr:` is in the task file.

**§9.3 corrected in the doc as you asked**, with the corrected staging table beside 032s original and the reason (the blitter walks the grid linearly, so items 5 and 8 cannot be split). §12.5 carries the EFLAGS account.

**Two more stage-2 defects found while queued, same family as the shroud pitch — a base rebase is not enough when the arithmetic around it is stride arithmetic:**

1. `0x004B1FA0` fills the grid from row 18 down and computes its BYTE COUNT as `40*(row-17)` (`lea ecx,[eax+eax*4-0x55]` + `shl ecx,3`). Re-pointing the base without rebuilding that count fills 40 bytes of every 50-byte row and leaves the right of each one unmarked. Rebuilt as `(row-17)*50` inside the same seven bytes.
2. `0x0048CB80` steps its own walk with `add ecx,0x28` — the grid stride again.

Both would have been missed redraws rather than crashes, which is precisely the class that survives into a screenshot. Table is now 142 sites, 129 written; `--check` green, flags check green, `run-ci-local.ps1` green.

**I am idle and I will not take the machine until you signal.** When you do, the order is: `test-widescreen.ps1 -Stage 1` (binary: pixel-identical to control or not), then `-Stage 2` only if stage 1 passes. If stage 1 fails I go static again.
