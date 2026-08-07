---
from: conductor
to: user
sent: 2026-08-06T23:57:54Z
subject: all merged, main green - one decision waiting
---

Update: everything merged. The Actions blocker I flagged resolved itself, and the whole night's work is now on main.

## Merged (5 tasks, 6 PRs, board clean)

  001  Ghidra headless pipeline          tools/ghidra/
  002  working copy + PE anatomy         tools/make-working-copy.ps1, tools/pe_report.py, research/
  003  12-unit selection-cap recon       research/selection-cap.md
  004  CI workflow                       .github/workflows/ci.yml
  006  CI exit-code fix                  main is now GREEN

Still running: 005, the first real Ghidra pass over StarCraft.exe.

## What happened with Actions

It started working on its own around 23:33 — so nothing for you to fix there. But all 8 runs then failed, and the cause was OUR bug, not GitHub's: the lint step probes with `pip show ruff`, which exits 1 when the package is absent. The script correctly took the "skip lint" branch, but the stale exit code survived and GitHub's pwsh wrapper failed the step *because the optional linter was correctly skipped*. Fixed, and the fix is correct on both paths — a real lint failure still fails the step.

Worth flagging: that is the THIRD instance of the same bug family in this repo (PowerShell exit-code / error-action semantics not matching intent). It is the dominant failure mode in our tooling, so I now have workers audit for it rather than fix one instance.

## The finding that changed the plan

I asked worker 003 to justify its "nobody has done this on 1.16.1" claim rather than assert an absence of evidence. Re-searching found a counterexample instead: two closed-source 1.16.1 tools described as selecting/commanding ~252-255 units. So the conclusion splits:

1. Array relocation (the heavyweight approaches) still looks untrodden.
2. Command fan-out — the approach I recommended as your first milestone — has precedent in a HUMAN-driven client on this exact binary, not just in bots. That de-risks it considerably.

The tell: all units obey the order, but only 12 selection circles draw and the extra count renders as text. That is the fan-out signature, and it confirms the tradeoff — you get the COMMAND, not the LOOK.

(The worker declined to download those tools — Battle.net cheat tools, out of bounds under our offline-only rule — and tagged the claims [unverified] since the sources are behind sign-in walls. Correct call.)

Candidate #1 also now has real sizing: ceil(N/12)+1 commands, ~359 bytes for a 100-unit order, which overflows the 255-byte replay frame block, so it must chunk across frames at ~4-5 pairs per frame.

## STILL WAITING ON YOU — one decision

Your words: "allow SELECTING more than 12 units."

1. Fan-out (days, low risk, precedented) -> you COMMAND 30 marines, HUD still shows 12.
2. Wide client selection (medium) -> you SEE more than 12.
3. Full engine change (hard) -> everything properly.

I recommend 1 first: it is playable fast and becomes the test harness for 2 and 3. Say the word and I cut it as soon as 005 lands.

## Housekeeping

- Your pristine install: hash verified UNCHANGED, checked repeatedly all night.
- 1.47 GB of merged worktrees pruned; board-lint clean.
- Two follow-ups queued (not urgent): a `Write-Error`-under-Stop bug in make-working-copy.ps1's verifier, and a `robocopy /MIR` guard so a mistyped -Destination cannot be purged.
