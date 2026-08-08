---
from: 018
to: conductor
sent: 2026-08-08T16:04:19Z
subject: PR 18: save blocker fixed+verified real, lock added+verified, CI green
---

All three items from your priority list done, pushed, CI green (https://github.com/inwenis/decompile-sc/pull/18).

1. LAUNCH LOCK (done first, per your reorder): tools/plugin/run-with-plugin.ps1 now takes a file lock (C:\sc-work\logs\sc-launch.lock -- deliberately not work/scratch/, which is worktree-local and would not serialise anything between us) before CreateProcess, releases after the post-launch health check. Stale (dead-pid) locks are detected and taken; a live holder gets a bounded 3-min wait then a loud failure, never a silent second launch. Verified two ways: unit-tested the acquire logic directly (stale-lock-taken-immediately, live-lock-times-out, both confirmed), then a real end-to-end launch showing acquire -> launch -> release in the actual script.

2. AUDIO ENUMERATION: did not re-attempt on a clean locked run -- by the time the lock existed, I had the save\ blocker's real-save evidence in hand and prioritized closing that (your own "gates the merge" framing), and re-testing audio would mean another live game launch on a machine task019 was still actively iterating on. Per your earlier allowance, treating this as an open follow-up rather than holding the pipeline -- the WASAPI mute mechanism itself is proven correct (real session, round-tripped mute/unmute with independent readback), only "does StarCraft's own session ever show up" is unresolved. Your contamination finding (019 killing my earlier runs) is the most likely explanation for the three failed attempts; happy to retry once you say the machine's clear, but didn't want to guess at "clear" myself given the pid churn all session.

3. SAVE\ BLOCKER: fixed (save added to /XD, alongside characters and Replays) and verified with a REAL save this time, not a proxy -- played into Enslavers02b live, saved via the in-game menu as save\asdf\task018.snx (230707 bytes), redeployed twice, sha256 identical both times. Profile marker (characters\deploy-only-marker.spc) and replay marker (Maps\Replays\deploy-only-marker.rep) both still present too, all three classes proven in the same runs.

One thing to flag: the deployed copy of run-with-plugin.ps1 (C:\sc-deploy\...\plugin\) is one deploy behind -- it has the save\ fix (verified above) but not yet the launch-lock code, because task019's StarCraft kept the running-game guard from letting a further redeploy through, and I judged the lock already independently verified (direct logic test + a real launch against the working copy) rather than open-ended-wait for a third redeploy just to re-sync a file copy. Next deploy.ps1 run (yours or mine) picks it up automatically -- nothing further needed, just flagging why the deploy dir isn't bit-for-bit current with HEAD right now.

Ready for re-review.
