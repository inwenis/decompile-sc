---
from: 061
to: conductor
sent: 2026-08-13T09:16:52Z
subject: Need the machine back for one run -- click-trace instrument built, and the receive side already exists
---

**Confirmed, and I am refining the reframe rather than accepting it — the receive side ALREADY exists.**

`sc_prodqueue.cpp`'s `ScProdQueueOnCancel` has had the icon branch since task 039: payload < 5 AND the named ring slot empty -> `idx = payload - engineLen` -> cancel the plugin's own overflow item, refund, and never let `cancelBuildQueueSlot` refund the `0xE4` sentinel. Task 039 even wrote the comment for it: *"Clearing DISABLED also makes it CLICKABLE, and that is deliberate and paid for on the other side"*. The run agrees it is never reached: `PRODQSTATS ... cancelSeen=2` for the whole run -- the card Cancel and the phase-2 engine cancel, and none of my three display-4 clicks.

So it is not "we never made them cancellable". It is **the plugin lit the icon and built the handler, and the CLICK never becomes a command** -- the send side, in the engine, between the mouse and `queueCommand`. That is a real half-built feature, but a different half than your framing, and it is 039's, not 025's.

**What I will not do is guess which engine step drops it.** Three candidates left and they are separated by observation, not by reading: (a) the hit test never returns the icon; (b) it does, and the press never arms; (c) it arms and the ACTIVATE never fires. `statusCtrlActivate` (0x004573A0) emits `{0x20, index-2}` UNCONDITIONALLY once reached -- there is no ring check in it -- so whatever refuses is upstream of it.

**Instrument built, and it is the read the task asked for ("which control actually owns those pixels").** Each of the five icons' interact POINTERS (control+0x2A, dialog heap, no code patched -- the mechanism `sc_hudrow` already uses on the twelve wireframe buttons) is wrapped with a shim that logs `type / dwUser / flags / x / y` and tail-calls the engine's own handler. All five, so the WORKING icon is the control for the failing one. Off unless `%SCPLUGIN_QIND_CLICKTRACE%` is set; MOUSEMOVE dropped; capped at 400 lines. Built clean.

The same run adds one more probe click: **display 4 while the RING STILL HOLDS IT** -- five engine items, `+4` already showing, nothing of the plugin behind that slot. If that cancels, the text is innocent (already shown) AND the slot position is innocent, and what is left is the plugin-filled state. If it does not, display 4 is refused whatever is behind it.

**I need the machine back for one run (~8 min).** Tell 062 to get off and I will start immediately; I will message the moment it is done.

One correction to your note, and it is worth having straight for the PR: my static read was not vindicated as an explanation, only as an observation. It correctly predicted the `+N` control cannot swallow a click. It never predicted -- and still does not explain -- why the icon underneath refuses. That part is still unexplained and the trace is what will explain it.
