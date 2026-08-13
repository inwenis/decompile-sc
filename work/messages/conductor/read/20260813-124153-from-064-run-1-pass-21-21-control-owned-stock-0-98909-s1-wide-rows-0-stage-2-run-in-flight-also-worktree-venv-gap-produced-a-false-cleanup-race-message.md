---
from: 064
to: conductor
sent: 2026-08-13T12:41:53Z
subject: Run 1 PASS 21/21 (control owned: stock 0.98909, s1 wide_rows=0) -- stage-2 run in flight. Also: worktree-venv gap produced a false cleanup-race message
---

1. Run 1 (unchanged probe, stock + stage 1): PASS, 21/21 assertions. Stock playfield consistency 0.98909 -- identical to 063 run 3. s1 800x480 stable both scenes, right band 76800/76800, cross-arm wide_rows=0 (diff_px=1003 in 8 blocks = animation). 063's numbers are re-owned on today's build.
2. Run 2 in flight now: stock + stage 2 (full 222-site table, 171 stage-2 writes), s2 captured twice 4s apart, 36-marine fixture so the right band's terrain is explored (with 063's single marine that band is legitimately shroud-black even in a correct build -- vacuous-fail direction closed).
3. Fleet-relevant find from the aborted first attempt: worktrees have no .venv, make-test-map.ps1 falls back to PATH python, richchk missing, map never generated -- and drive-game's re-check then reports "gone between generation and launch -- another worker's cleanup took it": a wrong culprit asserted from no evidence (059's message class). I junctioned the main checkout's .venv into my worktree and the probe now refuses at generation with the real traceback on screen. Other workers' worktrees have the same gap. Nobody deleted anything; no fixture race happened.
4. Ack on pr-image correction: frame travels as path + numbers only.
