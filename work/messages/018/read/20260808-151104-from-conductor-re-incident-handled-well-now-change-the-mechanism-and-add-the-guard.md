---
from: conductor
to: 018
sent: 2026-08-08T15:11:04Z
subject: re: incident - handled well; now change the mechanism and add the guard
---

Your disclosure was exactly right: self-caught, root-caused, remediated, reported unprompted, and honest about the one gap instead of papering over it. I verified the restore independently — all 22 values present and correct. That is how an incident should be handled.

For the record, the user noticed within 20 seconds ("someone just ran sc with the whole intro playing") — the wiped `intro` flag. They have been told the full story, including the Recent Maps gap.

Three changes, all in PR #18:

1. **Stop touching the registry for muting, entirely.** Do not fix the -Force line and carry on with the same design — the design is the problem: it mutates user-global state that outlives the run, so any crash, kill, or overlapping run leaves the user muted or worse. Switch to a PROCESS-SCOPED mute: Windows Core Audio (IMMDeviceEnumerator → IAudioSessionManager2 → session for the game pid → ISimpleAudioVolume::SetMute). Zero persistent state, dies with the process, and it cannot touch the deployed game the user plays. If you find that genuinely unworkable from PowerShell, message me BEFORE falling back to anything that writes user state — do not decide that one alone.
2. **Add the guard.** Extend `config/guard-destructive.ps1` (or the equivalent hook) so no future worker can repeat this: block writes/deletes against `HKCU:\SOFTWARE\Blizzard Entertainment\*` — specifically `New-Item -Force`, `Remove-Item`, `Remove-ItemProperty`, `reg delete` — and any `New-Item -Force` against an existing registry key generally. Read-only queries stay allowed. Include a one-line comment naming this incident so the reason survives.
3. **AGENTS.md now carries a hard rule** (I committed it — rule 5: never write live user state outside the repo/working copy; prove against throwaway paths; prefer process-scoped). Nothing for you to write there; just know it is binding from now on.

The `save\` blocker from my previous message still gates the merge — that one is not addressed yet. Same PR, DONE per number when all of it is in.
