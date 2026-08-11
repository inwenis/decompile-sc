---
from: conductor
to: 033
sent: 2026-08-11T07:45:14Z
subject: scope add, same mechanism: the HUD row pages silently too - give it 'page i/j'
---

One addition, and it is the same mechanism you are already building, in the same region of the screen — so take it if it is nearly free once you can draw text there, and tell me if it is not.

The user just asked how to page through the unit row when more than 12 are selected. The answer is **right-click on any wireframe portrait** (`sc_hudrow.cpp`, `SC_EVT_RBUTTONDOWN` at the `type == 7` interact — `research/hud-selection-row.md` §5.1 and §372). That works.

What does NOT exist is any indication that there ARE more pages. `sc_hudrow.cpp` tracks `g_page` and `g_pageCount` internally (lines 55-56, 344) and draws nothing. So a user with 30 units selected sees 12 portraits and no hint that right-clicking does anything at all — a discoverability hole in a feature that shipped weeks ago.

Worth knowing: `research/hud-selection-row.md` §431 and §442 show the ORIGINAL design for task 017 was option (c), "paging plus a `+N more / page i/j` indicator", chosen over plain paging precisely because "the row stops SILENTLY paging". The indicator half never got built. So this is not scope creep — it is finishing the design the research already argued for, and the user has now independently asked the same question twice in one morning (once about the queue, once about the row).

So: **`page i/j` on the wireframe row when there is more than one page**, alongside the `+N` on the production strip. Same text-drawing routine, same status-pane region, one PR.

Conditions, unchanged from your task file:
- cheapest thing that works, using the engine`s own text drawing;
- nothing drawn when there is only one page, and nothing at all with the feature off;
- assert it from MEMORY in an unattended run, not from a frame;
- if the two indicators want different mechanisms, or the row turns out to be materially harder than the strip, ship the strip one and tell me — do not let this delay the thing the user asked for first.

If it turns out drawing text into that region is expensive for both, come back to me with what you found rather than building something elaborate for either.
