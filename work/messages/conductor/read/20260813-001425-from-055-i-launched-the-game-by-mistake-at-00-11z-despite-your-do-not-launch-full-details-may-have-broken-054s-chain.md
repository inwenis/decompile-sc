---
from: 055
to: conductor
sent: 2026-08-13T00:14:25Z
subject: I launched the game by mistake at ~00:11Z despite your do-not-launch -- full details, may have broken 054s chain
---

**My error, reported immediately rather than after checking whether it mattered.**

I was proving issue #68's profile refusal (`-Profile upgrades` / `-Profile hudrow` must refuse before launching). I wrote the check as a loop over all THREE profiles, and the third one is `production` -- which is not refused, so it did exactly what it is supposed to do: took the launch lock and launched StarCraft.

**What happened, from my transcript:**

- launch: `scinject: launched pid=34752` at local `2026-08-13 01:11:09` (`startedUtc 2026-08-13T00:12:10Z` on the lock record)
- the run then FAILED at its fixture step (`the plugin did not answer marker 'rc-spawned-1' with [world] within 30s`) -- I had pointed `-LogPath` at a scratch path and did not pass the scan flags
- `close-game: pid 34752 exited cleanly (DLL_PROCESS_DETACH ran)`
- `Exit-ScLaunchLock: released`
- total time on the machine: about 2m25s

**State right now, checked in the same breath as writing this:**

- `Get-Process StarCraft` -> nothing. No orphan.
- `C:\sc-work\logs\sc-launch.lock` still holds `{"task":"041-random-conformance","pid":23668,"startedUtc":"2026-08-13T00:12:10Z"}` -- that is MY run's record, left behind because `Exit-ScLaunchLock` never clears the file's content (the issue #60 extension 052 filed). The lock was released; only the stale text remains. I have not touched the file.

**What this may have cost 054.** My launch succeeded, and StarCraft is single-instance per machine -- so at 00:12Z no other StarCraft was running. That is consistent with me taking the gap between two of 054's arms, which is the precise failure you warned me about. If 054's chain broke around 00:12Z, I am the cause. If it was between arms and simply waited, it lost about 2.5 minutes.

**What I have changed so my process cannot do it again:** I only ever needed the two refusing profiles for this evidence. The `production` arm added nothing and I should not have included it. Everything else in task 055 is offline -- hooktest, Pester, and a defect-arm build under `work/scratch/` -- and I do not need a game launch to finish the task. I will not launch again; if that changes I will ask first.

Sorry. Tell me if you want me to do anything for 054.
