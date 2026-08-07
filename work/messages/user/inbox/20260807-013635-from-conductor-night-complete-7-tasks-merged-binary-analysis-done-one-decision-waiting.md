---
from: conductor
to: user
sent: 2026-08-07T01:36:35Z
subject: NIGHT COMPLETE: 7 tasks merged, binary analysis done, one decision waiting
---

Night's work complete. Everything merged, main green, board clean, nothing broken. Your pristine install was verified untouched at every step.

# 7 tasks, 7 PRs, all merged

  001  Ghidra headless pipeline           tools/ghidra/
  002  working copy + PE anatomy          tools/make-working-copy.ps1, tools/pe_report.py
  003  12-unit selection-cap recon        research/selection-cap.md
  004  CI workflow                        .github/workflows/ci.yml
  005  BINARY analysis of the cap         research/binary-selection-map.md + 5 data tables
  006  CI exit-code fix                   main went green
  007  tooling hardening + docs

# What we actually know now (from the binary, not from the internet)

Task 005 opened StarCraft.exe and checked the addresses everyone else asserts. Results:

1. **All 35 inherited addresses are real.** Every one resolves to a genuine function entry point. The public prior art is trustworthy on locations.
2. **But one of its conclusions was wrong** — and it was the optimistic one. The recon claimed the order-dispatch loop was "bound-agnostic", calling it "the single most encouraging finding in this document". The binary has a hardcoded compare against 12 gating it. Confirmed by hand-decoding raw bytes, twice, independently. Corrected in the merged doc.
   Silver lining: the gate is in ONE shared iterator reached from 73 places, so it is one fix, not 73.
3. **Two long-standing disagreements between public sources are now settled** against the binary rather than by picking a favourite. The one that matters: the wire count is UNSIGNED, so the protocol ceiling is 255, not 127. A future implementation would have designed around the wrong number.
4. **Four of five arrays have zero slack** — each neighbour identified by name from references, not from guessing. This is the number that decides relocate-vs-extend.

Deliverables are committed as data tables (346 cross-references, 139 constants, 26 stride sites), regenerable by committed tooling — not hand-typed prose.

# STILL WAITING ON YOU — the one decision

Your words: "allow SELECTING more than 12 units."

  1. Fan-out          you COMMAND 30 marines; HUD still shows 12.   days, low risk, PRECEDENTED
  2. Wide selection   you SEE more than 12 selected.                medium
  3. Full relocation  everything, properly.                          hard

I recommend 1 first — it is playable fast and becomes the test harness for 2 and 3. But it is your call and I have not started implementation without it.

# How I worked

I did not take workers at their word. Every substantial PR got an independent verifier that re-did the work rather than reading the report. That caught, in order: two silent-wrong-answer bugs in the Ghidra pipeline (a failed run could report success; a documented option was a no-op); a circular argument in the research (its own arithmetic quoted back as evidence); and a classifier bug that mislabelled the single most load-bearing data row. None of these were in any worker's self-report.

Worth knowing: one worker pushed back on a review finding and proved the reviewer's reasoning wrong while the conclusion was right. That is the behaviour I want, and I told it so.

# Two mistakes I made

1. I told you StarCraft.exe was ~2.7 MB. It is 1,220,608 bytes. The wrong figure reached a doc before it was corrected.
2. I pruned a merged worktree that still held the only Ghidra install on the machine, and broke a running worker. Cost ~10 minutes. The install now lives at C:\re-tools\ outside every worktree, and the reason is documented in tools/ghidra/README.md so nobody repeats it.

# Housekeeping

- Pristine install C:\sc-install\Starcraft — sha256 verified UNCHANGED throughout.
- Working copy C:\sc-work\1161-base — resets to byte-identical in ~3 seconds, and I re-tested that path myself after the guard change.
- Two conductor-UI issues filed for you: #123 (vanishing messages / dual dir layout) and #126 (statusline inactive until session restart).
- One note: GitHub Actions had produced zero runs account-wide when I flagged it. It started working on its own; the 8 failures that followed were our own bug, now fixed.
