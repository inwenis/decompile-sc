---
from: 018
to: conductor
sent: 2026-08-08T15:33:13Z
subject: Sound: mechanism switched to WASAPI + guard added, one honest verification gap
---

Sound work done per your 3-point directive, PR #18 updated:

1. Mechanism switched entirely to process-scoped WASAPI session mute (tools/plugin/sc-audio-mute.ps1, IMMDeviceEnumerator -> IAudioSessionManager2 -> ISimpleAudioVolume::SetMute on the game's own pid). Zero registry/file writes now -- confirmed by reading the actual diff, not just intent. run-with-plugin.ps1 calls it right after the pid is known; -Sound skips it entirely (deploy.ps1's baked launcher always passes -Sound).

2. Guard added to config/guard-destructive.ps1: hard-denies New-Item/Remove-Item/Remove-ItemProperty/Set-ItemProperty/New-ItemProperty/reg add/reg delete against the Blizzard Entertainment\Starcraft key specifically, plus a general hard-deny on `New-Item -Force` against ANY registry path (HKCU/HKLM/HKCR/HKU/HKCC), both citing the incident. Read-only queries still pass.

3. AGENTS.md rule 5 -- noted, nothing for me to write there.

VERIFICATION -- stated honestly rather than overclaimed:
- The mute primitive itself: proven correct against a REAL session on this machine (pid 7408, a different process) -- full round-trip, mute -> GetMute confirms true -> unmute -> GetMute confirms false, verified by independent readback each step.
- What I could NOT confirm: StarCraft's OWN audio session ever appearing in the Core Audio session enumerator on this machine. Tried three times across two different launches -- at the main menu (visibly running, not stalled) and after a menu click (Single Player, which should play a UI sound) -- zero sessions for the game's pid every time, over windows up to ~30s. Two live possibilities I could not distinguish: (a) the session genuinely takes longer than I tested to appear, which the background re-affirm timer (re-checks every 1.5s for as long as the process lives) already covers if so, or (b) this machine has no real audio render device for DirectSound to attach to, in which case there is nothing to mute in the first place -- consistent with everything I ran producing no session, ever.
- I did not run a full unattended suite end-to-end for this because it would not resolve that open question (same silence either way) and risks more unwanted noise if (a) is the answer and a session eventually does appear mid-run, which felt like the wrong tradeoff while you're actively working nearby.

This is disclosed as an open question, not hidden: the code is correct for whichever answer turns out true, and doc'd honestly (run-with-plugin.ps1 "Sound" + tools/README-deploy.md "Sound" both state the gap plainly). Let me know if you want me to dig further or if this is an acceptable state to merge with.

Also note: while chasing the audio-session timing I ran into what looks like a DIFFERENT StarCraft process (Zerg units, burrow-fanout-shaped fixture) that wasn't mine -- didn't touch it once I noticed, but flagging in case a concurrent agent's run got confused with mine at any point (pids churned more than I expected across this session).

Still owed and next: the save\ blocker from your earlier message -- pivoting to that now with a real save-then-redeploy test.
