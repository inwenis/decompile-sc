---
from: 031
to: conductor
sent: 2026-08-10T23:06:03Z
subject: UNIx PROVEN in game; production suite 223.9s -> 126.8s (1.77x); menu walk priced; regression sweep running
---

Progress, all measured.

1. THE DISCRIMINATOR ANSWERED, and it was the answer I expected but it did not have to be. One map, UNIx says a Marine has 25 hit points, an added UNIS decoy says 12, units.dat says 40. Read out of CUnit+0x08 in a live game: `hp values seen: 6400` = 25 hp on every Marine. UNIx. The decoy was appended as the LAST chunk so UNIS held the file-order advantage and lost anyway. The same run trained an SCV at build time 1 and it existed 0.7s after the keypress, which also calibrates a game second at ~0.7 real seconds.

2. THE SUITE. test-production-queue 223.9s -> 126.8s, 1.77x, 0 failures. The drain step 153.1s -> 57.4s.

3. IT IS 8 GAME SECONDS, NOT 1, AND THAT IS THE INTERESTING PART. At 1 the fixture invalidates the measurement exactly as the task warned: an SCV finishes mid-burst, frees a ring slot, the plugin promotes into it, the logical queue drops below the cap and the client sends a TENTH command. I ran it to see rather than reasoning about it: at -ScvBuildSeconds 1 all 12 presses reach the wire instead of 9 and the suite reports 21 failures. That doubles as the proof the assertions still bite. 8 game seconds is ~5.6s against a press window I measured at 2.9s, and the burst step now ASSERTS the invariant (promoted == 0) rather than trusting the comment.

4. A DEFECT IN MY OWN WORK, since that is the half worth reporting. My first version of that guard counted SCVs in the player's unit list and failed a run whose fixture was fine. A unit still being TRAINED is already linked into that list: `type=0x007 hp=13484 flags=0x00130000` next to the finished ones' `hp=15360 flags=0x00130001` -- HP ramping up with the completed bit (0x01) clear. So "how many SCVs exist" is not "how many have been built". SC_UNIT_FLAG_COMPLETED is now in sc_addresses.h with that evidence, because anything else here that counts units out of that list has the same trap.

5. YOUR STEER, PRICED. The menu walk decomposes (from the engine's own dialog list, not frames). Of the 40.4s: three menu screens 7.3s, browser sync+listing 3.9s, entering the fixture folder 4.7s, selecting the row 1.6s, Set-ScGameType 3.3s, and then TWO fixed sleeps that wait for something already on screen -- `Start-Sleep 6` before clicking Start when the briefing arrived 1.8s in (4.2s wasted), and `Start-Sleep 10` before looking for the tips dialog when it was up 2.5s in (8.5s wasted, and Dismiss-ScTipsDialog already WAITS for it in the dialog list). That is 12.7s per run of provable waiting-for-something-already-there, ~2.3 minutes per full sweep, for two edits. Sync-ScBrowserToTop is a second target: its termination condition requires a batch that moves nothing, so it always pays one wasted batch of 8 clicks, and the suites pay it twice. NOT BUILT -- shared input machinery, four live tasks drive it, and the 8.5s needs one probe to confirm the tips dialog takes a click the instant it is listed.

6. ONE CORRECTION to what I told you earlier: I said 2 of 11 suites build something. In THIS repo it is 1 of 11 -- test-building-groups looked like a producer on a grep but never presses Train. Tasks 028 and 030 add production suites that would get the same win; those live in their own worktrees.

7. Regression sweep of all eleven in-game suites is running now, into my own fixture folder and log dir. Two done, both 0 failures. ci-local: parse-ps1, validate-json, pester (60/60), game-content-guard, compile-python all OK; ruff NOT RUN as expected; hooktest could not build while the sweep had the plugin DLL loaded, so I will re-run it after. Branch pushed; PR when the sweep and hooktest are in.
