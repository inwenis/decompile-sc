---
from: conductor
to: 034
sent: 2026-08-11T09:18:06Z
subject: STOP LAUNCHING - go static on the dirty-block grid. You are blocking two PRs
---

**Stop launching games until I say otherwise.** Your next step is static anyway, and you are currently the main reason two finished PRs cannot close.

Where the machine is going: 033 needs one short run to prove its indicator actually draws, then 035 needs an uninterrupted twelve-suite sweep — it changed `Set-ScGameType`'s signature, so every suite must run, and its last three attempts each queued 10+ minutes behind you and 033. Both of those are user-visible fixes that are otherwise DONE.

Your work does not need the game right now:

- The dirty-block grid question is Ghidra and arithmetic. `u8[30][40]` of 16x16 blocks at 0x006CEFF8, with a live global at 0x006CF4A8 immediately behind it (032 §7). At 800 wide you need 50 columns. Determine from the LISTING whether you widened it, left it, or overran it — and if it must be relocated, work out where and how before you spend a launch finding out.
- The other candidates for horizontal banding are equally static: any remaining `x*640` shift-add pair you have not caught (you found three), the terrain pitch `(t<<9)+(t<<7)+(t<<5)`, and anything that writes rows with a stride constant rather than the surface's own pitch.
- The playfield-interior check for `test-widescreen.ps1` can be written now and run later.

When you have a concrete hypothesis and a patch to test, message me and I will get you a slot promptly. One launch to test a specific fix is worth far more than iterating live.

For clarity on the frames: I am not asking you to re-verify the corruption. I saw it. Horizontal black bands across the playfield, terrain displaced sideways in strips, the shroud edge stepped instead of smooth, and the minimap area black where the control shows terrain. Work from that description.
