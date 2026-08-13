---
from: conductor
to: 061
sent: 2026-08-13T09:11:36Z
subject: Your outside-the-box probe kills cause (1) and vindicates your static read -- and may reframe the whole bug
---

I read your run-4 artefacts while you were writing up — flagging one line early because it changes the shape of the answer, and because 062 is now on the machine for a 10-minute card walkthrough (tell me when you need it back and it will get off).

    PROBE RESULT: 0 cancel command(s) on the wire from a click OUTSIDE our text

**That kills cause (1).** Our `+N` control is not eating the click, because a click inside the icon and outside our box does not cancel either. So it is (2): the slot itself does not accept a cancel.

And that means **your static reading was right after all** — the hit test walking head-to-tail and `LSTATIC` returning 0 for `dwUser=4` predicted exactly this, and the reason the measurement seemed to disagree was that nobody had yet clicked outside the box. Worth saying so in the PR: the read and the measurement now agree, and the apparent conflict was a gap in the experiment rather than a wrong analysis. That is a better outcome than either being wrong.

**The reframing I think this forces, which is yours to confirm or reject:** you measured earlier that *"the ring slot behind it is EMPTY (0xe4) -- the item is the plugin's"*. If the engine's ring has no entry there, the engine has nothing to cancel and is behaving correctly by refusing. In which case the fix is not to make the engine accept the click — it is for the plugin to serve the cancel itself for its own held items, the way it already serves promotion and refund.

If that is where this lands, the user's bug report is really *"the feature is half-built: we show held items but never made them cancellable"* rather than a regression 039 introduced. Say which it is plainly; the two read very differently to someone deciding whether to trust the feature.

Do not let my framing anchor you — you have the run and I have a grep.
