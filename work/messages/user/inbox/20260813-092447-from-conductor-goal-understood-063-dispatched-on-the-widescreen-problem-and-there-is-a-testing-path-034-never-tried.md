---
from: conductor
to: user
sent: 2026-08-13T09:24:47Z
subject: Goal understood -- 063 dispatched on the widescreen problem, and there is a testing path 034 never tried
---

Understood, and the goal is now the priority. **Task 063 is dispatched on fable** — the widescreen presentation problem, framed exactly as you put it: *see more of the map, and find a way to test it without touching your screen.*

## The insight it is testing first, because it might make this cheap

Task 034 stopped because *"every frame this task has ever captured shows only the left 640 columns"*. But those frames were captured **through the presented window**.

The engine's own framebuffer is a flat surface at a known address, and at stage 1 it is demonstrably 800 wide — allocated, verified, 384,000 bytes. **Reading that surface directly should show all 800 columns regardless of what the window puts on your monitor.** This project already reads engine surfaces that way: the `boxDiff` oracle that proved your queue indicator and your page indicator both work reads the dialog's own 8-bit surface.

If that generalises to the main framebuffer, then 034's blocker was a property of its **instrument**, not of the engine — and stage 2 becomes developable today, with zero impact on your screen. That is the first thing 063 will answer, with a stock 640-wide frame as its positive control before it trusts anything at 800.

If it does not work, it says so at 034's standard and moves to costing the presentation routes properly.

## What it will not do

It will not switch your desktop mode. If a fullscreen mode switch is worth measuring, it measures it on the **invisible desktop** (the one tests already run on, that you never see) and reports whether the switch is per-desktop or per-adapter — which nobody actually knows.

It also will not grind on stage 2. Stage 2 is a separate, larger problem and 034 established it does not decompose; 063 exists to make it *testable*, not to solve it.

## Housekeeping

Noted on stacking: I will not hold work waiting for merges. Where a task depends on another's unmerged branch it will branch from it and say so.

**061** is close on your cancel bug — it has instrumented all five queue icons to find which engine step drops the click. **062** has your test map built and needs ten minutes of machine time to walk its card. Both continue.
