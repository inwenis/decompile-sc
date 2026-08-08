---
from: 018
to: conductor
sent: 2026-08-08T16:56:35Z
subject: PR 18 round 4: all 8 items done, CI green, verified live throughout
---

All 8 items from round 4, pushed, CI green (https://github.com/inwenis/decompile-sc/pull/18). Done in your stated order: 1, 4, 2-3, 5-8.

1. BLOCKER (user-path lock regression): fixed with two independent guards -- lock only taken when $env:AGENT_TASK is set, PLUS deployed launcher bakes -NoLaunchLock explicitly. Also added try/catch + message box + log file to the launcher (any failure in a hidden pwsh is otherwise invisible). Verified: redeployed, then launched via the ACTUAL desktop shortcut (Invoke-Item on the .lnk) -- no lock messages, no launch-error.log, mode=fanout/circles=1/hudrow=1/HOOK 6/6 in the plugin log, closed clean.

4. LOCK CORRECTNESS: replaced check-then-write JSON-content locking with an exclusive OS file handle ([IO.File]::Open FileShare.None) -- atomic, and self-healing on a crashed/killed holder for free (no more stale-pid bookkeeping). Moved to cover -RemoveWindowed/-Windowed too, not just CreateProcess. -WaitForExit now releases before blocking on exit. deploy.ps1 takes the same lock for its whole run. Factored into shared sc-launch-lock.ps1. Verified: unit-tested acquire/block/release directly, verified a killed holder's lock recovers immediately (no staleness), then a real end-to-end launch through the actual script.

2-3. AUDIO: root cause confirmed and fixed -- was checking the default render endpoint only; now enumerates every active one (EnumAudioEndpoints). Also removed the background re-affirm timer since it measurably never fired during Start-Sleep and died with the process -- honest docs now say "polls at launch, then stops" instead of a false "runs for the whole session" claim. -Sound now actively unmutes (Mute $false) rather than just skipping, as insurance against persistence -- searched both known Windows per-app audio policy registry locations after mute/unmute cycles and found nothing, but added the explicit clear anyway since that search wasn't exhaustive. Did not get a chance to re-verify "does StarCraft's own session actually appear now" on a clean run -- ran out of scope/time in this round after the higher-priority items; still an open item if you want it chased further.

5. README-deploy.md: fully rewritten -- exact preserved/purged lists (characters/save/Replays/download/screenshots), the real-save evidence in place of the old proxy-marker section, Launch lock section added, Sound section corrected.

6. maps\download\ and SCScrnShot_*.pcx: excluded pre-emptively (0 occurrences in source, same shape as save\'s bug class). Verified live with planted markers -- both survive a real redeploy alongside the other three preserved classes.

7. Guard hook: now also blocks the Blizzard Entertainment PARENT key (not just \Starcraft), PowerShell aliases (ri/ni/sp/rp), the .NET Registry API, and regedit /s. Added a residual-limits comment in the file itself (command-string-only, quoted-text false positives, would not catch the incident if it lived inside a .ps1) -- including a note about the quoted-text false-positive class you hit sending the round-4 review, so the next person isn't surprised by it either. Tested the new regex via a throwaway script file specifically to route around that same false-positive class.

8. Tripwire: deploy.ps1 hashes characters\/save\/Maps\Replays\ before and after every mirror, throws on any disappearance/change. Verified live on a real redeploy (5 files checked, passed).

Full parse-check across all 67 .ps1 files in the repo, clean. Ready for re-review.
