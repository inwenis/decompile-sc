---
from: conductor
to: user
sent: 2026-08-06T22:39:42Z
subject: strategy: read in C, patch in asm, build mods in C++ (and your 1GB is art)
---

Install confirmed at C:\sc-install\Starcraft — genuine 1.16.1. Fingerprint:

  StarCraft.exe   1,220,608 bytes  v1.16.1  sha256 AD6B58B2...88C6A46
  storm.dll         409,600 bytes  v1.16.1
  battle.snp        557,310 bytes  v1.16.1
  total install   1,068 MB / 242 files

## 1. "what is 2.7 gb?"

My error — I said 2.7 MB (megabytes, not GB) for StarCraft.exe, and even that was wrong. Real exe is 1.22 MB.

Your ~1 GB download is almost entirely ASSETS, not code:
  StarCraft.mpq  483 MB   BroodWar.mpq  473 MB
  StarDat.mpq     61 MB   BrooDat.mpq    23 MB
= ~1,040 MB of MPQ archives: audio, video, sprites, maps.

The CODE we actually reverse-engineer is tiny:
  StarCraft.exe 1.22 MB + storm.dll 0.39 MB + battle.snp 0.54 MB ~= 2.2 MB total.

That is great news — 2.2 MB of x86 is a tractable target. The 1 GB is just art we never touch.

## 2. "assembly or C/C++?" — BOTH, at different layers. Recommendation:

Three layers, each with a job:

  1. Ghidra decompiled C = THE MAP, not the product.
     We read it to understand what code does. We never try to recompile the whole game from it.
  2. Assembly / byte patches = THE SCALPEL.
     For tiny changes (flip a constant, invert a comparison). Fast, low risk, instantly playable.
  3. Injected DLL written in real C/C++ = THE WORKSHOP.
     For actual features. We write normal C++, compile it with a normal compiler, and hook it into the
     running game. This is how the serious StarCraft modding scene works, and it is how we get the
     12-unit selection cap.

So: you DO get to write C/C++ — just not by decompiling 1.2 MB into a buildable source tree.

## 3. Why NOT full decompile-to-C-and-rebuild

Honest assessment: no debug symbols, unknown 1998 compiler, hand-tuned asm inside. Projects that did this
for comparable games took YEARS with teams — and it would not get us to your selection-cap goal any faster.
Wrong tool for the goal.

## 4. What "decompile it and compile it again, check it still works" becomes

I am keeping your task 1, in its meaningful form: prove the full loop on ONE function.
  decompile one real function to C -> recompile it -> inject it -> game runs with OUR code in it.
That validates the exact technique the selection-cap mod needs, in a day instead of a year. If it survives
that, the pipeline is real.

## Safety rule I am enforcing

We NEVER modify C:\sc-install\Starcraft directly — workers copy it to a scratch dir and patch the copy, so
your install always stays clean and playable. Offline/single-player only, never Battle.net.

Next: cutting the working-copy + PE-anatomy task now (runs without Ghidra). Worker 001 is still building
the Ghidra pipeline. Shout if you want the strategy called differently.
