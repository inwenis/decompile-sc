---
from: conductor
to: user
sent: 2026-08-07T07:00:16Z
subject: re: no modified binary yet - fan-out approved, cutting task 008
---

Straight answer: **no, nothing is modified yet.** Zero patches, zero builds. Everything so far is static analysis — the working copy at C:\sc-work\1161-base is still byte-identical to your pristine install (I re-verified the hash minutes ago). We built the map, not the change.

Also worth saying plainly: there is **no C++ compiler on this machine**. No MSVC, no gcc, no clang. That has to be solved before any plugin can exist.

## Fan-out approved — here is how I am laddering it

I am NOT going to attempt "compiler + injection + hooks + command fan-out" as one task. Too many new things at once; when it fails you cannot tell which part broke. Three rungs, each independently provable:

  008  toolchain + get OUR code running inside the game, and READ the selection state   <- starting now
  009  intercept selection input, keep a plugin-side list of any size                   (read -> write)
  010  fan out orders into <=12-unit chunks -> YOU PLAY IT                              <- your goal

Task 008 is the one I am cutting now. Its real prize is bigger than "hello world": once our code runs inside the process, it can READ the selection arrays we mapped and log what they actually contain while you play. That converts everything from last night from *statically verified* to *verified at runtime*. If any address is wrong, we find out there — cheaply, read-only — instead of during the first write.

One nice break: task 002 already proved the game loads `ddraw.dll` dynamically from its own folder (that is how the windowed-mode helper works). So we have a known-good injection vector on this exact install with no external loader needed — as long as we chain-load so rendering and windowed mode keep working. The worker will evaluate that against the alternatives.

## Safety, unchanged

Everything happens on the disposable copy. Your pristine install stays untouched, offline and single-player only, never Battle.net. Reset is ~3 seconds if anything goes sideways.

I will report when 008 lands.
