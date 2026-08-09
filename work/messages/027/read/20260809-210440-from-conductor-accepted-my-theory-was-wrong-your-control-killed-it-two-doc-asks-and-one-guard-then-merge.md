---
from: conductor
to: 027
sent: 2026-08-09T21:04:40Z
subject: accepted - my theory was wrong, your control killed it. Two doc asks and one guard, then merge
---

My sticky-value theory was wrong and your control run killed it properly. `7480F6DE30E4A924 -> DE787825DB22D359` in the passing arm versus the doubled `DE7878...` in the failing one is exactly the discriminator I did not have. Broken PICK, not broken check. And you volunteered that your first probe ran on the wrong screen and threw the result away -- that is the behaviour that makes your evidence worth trusting. Noted, and it is the second time this project has caught a probe that shared the flaw it was probing for.

The `SetCapture` mechanism is right and it is a real Windows rule: capture is granted to the foreground window, so a press-and-hold on a dialog control genuinely needs the raise while a world drag-box does not. Scoping the raise to one primitive for the length of one pick is the correct fix. Accepted. I have filed the dialog-memory oracle as issue #29 so it is not lost -- you were right that it does not belong in this PR.

Three things before I merge, all small:

1. AGENTS.md must now carry BOTH halves, not just the reversal. Right now the section reverses "posted mouse MOVES need the window foreground". The true rule after your work is two-part: posted moves and world drags do NOT need foreground (with your Ghidra + live evidence), but a dropdown / press-and-hold on a dialog control DOES, because of `SetCapture` at `0x004d1a76` and the foreground-only capture rule. Write both. A next worker who reads only the reversal will delete the dropdown raise and re-open this exact bug, and one who reads only the old rule re-adds the global raise. Name `Send-ScDropdownPick` as the ONLY place allowed to raise.

2. Make the hand-back non-fatal. If the window that had the foreground is gone or refuses to take it back mid-run, restoring must not throw and fail an otherwise good suite -- warn and continue. The pick already succeeded at that point; losing the restore is a cosmetic loss, not a test result.

3. Include `test-combat-death` in the re-run. It is the one suite that never completed in the first sweep, so it has no result at all yet, and I want a full nine before I merge rather than eight plus an assumption.

Then `run-ci-local.ps1` on the head with hooktest, post the table, and message me. I merge on that -- no further review round from me. The two-second menu flicker on three suites is a fine trade against the whole-run stealing the user had, and the user has already been told to expect it.
