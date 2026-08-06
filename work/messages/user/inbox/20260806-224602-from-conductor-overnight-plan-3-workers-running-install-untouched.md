---
from: conductor
to: user
sent: 2026-08-06T22:46:02Z
subject: overnight plan — 3 workers running, install untouched
---

Good night. Plan for the night, and what you will wake up to.

## Running now — 3 workers, your concurrency cap

  001 ghidra-headless        DONE -> PR #1 open, under review
  002 working-copy-baseline  safe copy of the game + PE anatomy + does-it-launch
  003 selection-cap-recon    recon on the 12-unit cap (the north star)

## What I did with the install

Fingerprinted C:\sc-install\Starcraft — genuine 1.16.1, matches expectations. I am NOT touching it.
Task 002 makes a working copy at C:\sc-work\1161-base and every patch happens there, so your
install stays clean and playable no matter what happens overnight.

## The ladder

  1. toolchain               001, done pending review
  2. working copy + anatomy  002, running
  3. round-trip proof        cut once 001+002 land: decompile one real function -> recompile ->
                             inject -> game runs with OUR code in it
  4. first easy mod          you play something visibly changed
  5. NORTH STAR              raise the 12-unit selection cap

## Overnight rules I am holding myself to

- Never modify your pristine install. Never go online with the game. Offline/single-player only.
- Every PR gets reviewed before merge — I dispatch an independent verifier that actually RE-RUNS
  the work rather than trusting the worker's claim. PR #1 is in that step right now.
- No game binaries or assets ever committed. The repo holds findings and tooling only.
- I will not do anything destructive or irreversible while you are asleep. Anything that needs
  your call waits for you here.

## One correction I owe you

I said StarCraft.exe was ~2.7 MB. Wrong — it is 1,220,608 bytes (1.16 MB). Real code surface is
~2.2 MB across exe + storm.dll + battle.snp. Even better than I told you. That error leaked into a
doc; I am having it fixed.

You will find a summary message here in the morning with what merged, what broke, and what needs
your decision.
