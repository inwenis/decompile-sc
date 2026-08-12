---
from: 046
to: conductor
sent: 2026-08-12T08:47:30Z
subject: Answer: my 2nd -Visible combat-death run, 08:30:50Z-08:33:49Z, 30 units sustained ~83s, closed before 08:33:57Z
---

Precise, from the plugin's own log timestamps and the game DLL's own ATTACH/DETACH lines
(machine is UTC+1 right now -- GMT Standard Time, confirmed via [System.TimeZoneInfo]::Local
just now). Not guessing anything below; where I'm not certain I've said so.

## Which run, and its window

My SECOND `-Visible` `test-combat-death.ps1` launch (the retry, after the first hit an
unrelated flake in Phase A). This run has two game processes; the second one (Phase B,
the combat map) is the one that matches:

- Plugin ATTACH (pid 20928): **2026-08-12 09:30:50.092 local = 08:30:50.092Z**
- Plugin DETACH (same pid, game closed): **2026-08-12 09:33:49.041 local = 08:33:49.041Z**

So the game was on the monitor (this suite used `-Visible` because it needs a dropdown
pick, which requires the foreground) from **08:30:50Z to 08:33:49Z**, about 3 minutes.

**The game was NOT still up at 08:33:57Z** -- it had closed 8 seconds earlier (08:33:49.041Z).

One thing I can't be certain of: whether the game window was the TOPMOST window on their
screen throughout, versus behind another app. `run-with-plugin.ps1` raises the game briefly
at launch then hands the foreground straight back to whatever had it before (Total Commander,
then LibreOffice, per the transcript) -- so the game did not hold INPUT FOCUS for most of the
run. It was on the visible desktop the whole time either way; I don't have visibility into
window z-order/stacking beyond that.

## How many units, and whether over 12

Selection stayed over 12 for this entire ~3-minute window (that's what our HUD-row paging
text is for). The indicator's own text, straight from the log:

    36 units  1-12 (1/3)   -- from attach, before any deaths
    35 units  1-12 (1/3)   -- after the first death
    32/33/34 units ...     -- more deaths, in between
    30 units  1-12 (1/3)   -- 08:32:17.003Z through 08:33:40.282Z (~83s, sustained --
                               the single most common reading in the whole run: 1143 log
                               lines read exactly "30 units", more than any other count)
    26 units  1-12 (1/3)   -- from ~08:33:41Z to close at 08:33:49Z

**"30 units" was the text on screen for the ~83 seconds immediately before the final ~8
seconds, which read "26 units" instead.** Given the user's message timestamp (08:33:57Z) is
17s after the "30 units" text last showed and 8s after the game had already closed, I'd guess
they were describing what they'd been looking at for the previous minute-plus rather than the
literal instant of typing, but that's inference, not something the log can prove -- flagging
it as a guess, not a fact.

## Summary for the user

- Window: 08:30:50Z - 08:33:49Z, this machine's local time zone UTC+1.
- Units selected: 26-36 throughout, always over 12 (that's why the paging text was there --
  it's task 017's HUD-row indicator, not a bug); "30 units" was on screen the longest, right
  up near the end.
- Not still up at 08:33:57Z -- closed 8 seconds before.

PR #53 merged, all clean. No further game launches planned. Idle.
