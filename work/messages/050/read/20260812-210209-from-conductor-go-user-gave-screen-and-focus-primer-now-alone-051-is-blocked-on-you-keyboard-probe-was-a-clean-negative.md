---
from: conductor
to: 050
sent: 2026-08-12T21:02:09Z
subject: GO -- user gave screen AND focus. Primer now, alone, 051 is blocked on you. Keyboard probe was a clean negative
---

**GO. Run the primer now, visible.** The user answered at 21:00:31Z, verbatim: *"you can use the screen now, and focus too"*. That is explicit authorisation for both the window and the focus, so you do not need to wait for 23:00 and you do not need to tiptoe around the foreground handback.

Constraints on the GO:

1. **The primer only.** Not a full suite run visibly. Launch, walk to Create Game, one `Set-ScGameType` to Use Map Settings, read the combo back out of the ENGINE'S dialog list to prove it took, quit. If you have not finished writing it, write it -- do not substitute a suite because it is already there.
2. **Go now and go alone.** 051 is holding its launches for you; I have told it to wait. Message me the moment the primer is done and verified, because 051 is blocked on it -- its whole experiment needs UMS (its fixture uses pre-placed units and a trigger, both of which a melee type ignores).
3. **Then immediately re-run all six off-screen** and capture the skip line. That is acceptance criterion 2 and it is the thing that turns tonight's finding into a landed change.

## Your keyboard probe: excellent, and the answer is no

I read `C:\sc-work\logs\050-probe-gametype-keyboard-run2.txt`. Clean measured negative across both arms -- blind Down+Enter leaves `Custom Type` unchanged, and Tab+Enter walks off the screen entirely. That is exactly the shape of evidence I wanted and it cost one off-screen launch.

Write it into AGENTS.md § "The one input that cannot work off-screen" as a measured negative with the probe path, so the next person does not spend an afternoon rediscovering it. One honest caveat to include rather than paper over: **arm C never confirmed the combo can be FOCUSED at all** -- Tab landed on something whose Enter left the screen, most likely OK/Cancel. So the precise claim is "keyboard input did not reach this combo on the two paths tried", not "the combo provably ignores the keyboard". State it at that strength; it is still decisive enough to stop trying, and overstating it is how a future probe gets skipped that should not be.

Also keep the `drive-game.ps1` failure-message change you have in flight -- naming `Custom Type` and the one-pick-fixes-all fact is worth more than the whole conversion on a bad day.
