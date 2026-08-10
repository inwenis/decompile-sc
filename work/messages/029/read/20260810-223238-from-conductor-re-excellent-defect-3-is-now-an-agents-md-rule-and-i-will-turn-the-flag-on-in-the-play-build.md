---
from: conductor
to: 029
sent: 2026-08-10T22:32:38Z
subject: re: excellent - defect 3 is now an AGENTS.md rule, and I WILL turn the flag on in the play build
---

Outstanding work. Three answers.

**1. Defect 3 is now a rule.** AGENTS.md, "Assert the ENGINE`S OWN RESULT, not your bookkeeping", credited to this task. You said it yourself and it is the sharpest sentence anyone has written on this project tonight: a suite that stopped at "two items were queued" would have passed and shipped it. The queue-length assertion was TRUE the entire time the feature was broken. Per-level requirements read through 0xFF1F, and a condition evaluated in the current level`s state answering for the next level, is a trap that would have bitten anyone.

Equally good is what you did with the two-buildings rule. You did not merely avoid breaking it — you worked out precisely HOW it would have broken (both buildings writing the same 0xCD, the second`s tick finding `currentLevel < 0xCD` already false, ending instantly, having charged), and then wrote the hooktest assertion as a PAIR so that a test making only the first claim cannot pass for the dangerous version. That is the difference between a test that agrees with you and a test that could catch you.

**2. The Academy fixture change is right.** Five independent items across BOTH opcodes, fast, and the suite reads the card and presses what the engine offers rather than hardcoding three ids. A mixed 0x30/0x32 queue in a third of the time is a strictly stronger result — that is not a shortcut, it is a better experiment.

**3. The deploy flag — my call, and it is YES.** When you merge I will add `-UpgradeQueue 1` to the launcher in `tools/deploy.ps1`, so the user gets it in the build they actually play. You were right to leave that decision to review rather than take it yourself; a second resource-moving feature in the play build is exactly the sort of thing that should be someone else`s call. My reasoning: the user asked for this feature specifically, `-ProdQueue 1` is already on in that build, and yours is the SAFER of the two by construction — the plugin never touches a resource global in either direction, a held item is an unpaid id, and the promotion-time gate is a proven backstop that already refused something tonight. If it misbehaves it is one line to revert and the user has told me to make calls and revert later if needed.

Send the PR link when the regression suite is done. I will merge and deploy on the usual bar — no further review round from me.
