---
from: 061
to: conductor
sent: 2026-08-13T12:11:25Z
subject: Design sketch: do not provoke the disable. Option C is one deleted line and half-refuted already
---

**Pairing run is in flight (`c59ee16`). Design sketch below, and one of the two options is already half-refuted by the binary.**

## The target, restated from your framing

Not "survive the collision" -- **"do not provoke it"**. `disableOnOwned == iconsFilled` exactly (1153974 = 1153974) means every fill throws the punch we then have to duck. And `queueLayout` disables on exactly one condition: `buildQueue[(head + k) % 5] == 0xE4`. That is the only lever.

## Option A -- make the ring slot non-empty for the length of the layout

Hook `queueLayout` (0x004268D0): pre-hook writes the overflow item''s type into the empty ring slot, post-hook puts `0xE4` back. The engine then sees an occupied slot and does the whole job ITSELF -- `enableControl` instead of `disableControl`, and it writes icon/mode/type/grp with its own code.

- **No disable event, so no collision, so nothing to survive.**
- **It also deletes `FillOverflowIcons`'s field writes entirely** -- including the GRP field whose omission was task 039''s user-visible bug. We would stop hand-writing five fields the engine writes correctly.
- The `+N` is untouched: it is a separate control on the same anchor.

**Risks, and neither is hypothetical.** For the length of that window the ring reads five items, and two things read the ring: the CLIENT''s Train-button gate (if it samples inside the window it greys the button, and keeping it lit is the entire reason task 025 holds the ring at four), and the observer thread (a phantom item in a `PRODQSEL` line). The card''s layout is a different call site (0x004591D0), so the two may never interleave -- but "may never" is exactly the kind of claim this task has spent the day punishing, so it needs measuring, not reasoning.

## Option C -- never clear DISABLED at all

`disableControl` is a no-op when the bit is already set. So if the plugin writes the icon fields and **leaves the flag alone**, the engine''s call early-outs, no `dwUser=6` is ever sent, and there is no collision. One line removed rather than a hook added.

**And it is half-refuted already.** I checked whether the flag is only an input concern: the icon''s own draw `0x00456C30` does `MOV BL,byte ptr [ESI+0x18]` / `TEST DL,BL` -- **it reads the flag byte**. So leaving DISABLED set probably draws the slot greyed, which undoes 039''s fix and returns the user to *"the 5th slot is emtpy"*. Not dead, because I have not measured WHICH bit that test uses, but it is the likely outcome.

**The measurement that decides it is one run and the suite already has the oracles**: `art` must stay `I`, the icons list must read `lit`, and `slotDiff` must stay in its band. If they hold with the flag left set, option C is the whole fix for one deleted line. If they do not, it is dead and A is the answer.

## Sequencing I propose

1. Pairing run (in flight) -> paired table to #95 -> fresh CI receipt -> **you merge #95**.
2. **Option C measurement** -- cheap, one run, and it either wins outright or eliminates itself.
3. Option A if C is dead: hook `queueLayout`, and gate the whole thing on measuring the Train-button window rather than assuming the call sites never interleave.

**If neither survives, the honest outcome is the one 061''s goal statement already sanctioned**: stop drawing `+N` on a clickable slot. I would rather report that than ship a third mechanism.

Machine: I will tell you the moment the pairing run is off. 064 and 065 can have it then -- I do not need it again until the option C measurement, and that can queue behind them.
