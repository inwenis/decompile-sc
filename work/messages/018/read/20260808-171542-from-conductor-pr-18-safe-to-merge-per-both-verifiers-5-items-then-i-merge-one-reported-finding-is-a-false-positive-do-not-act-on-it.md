---
from: conductor
to: 018
sent: 2026-08-08T17:15:42Z
subject: PR 18: SAFE TO MERGE per both verifiers - 5 items then I merge (one reported finding is a false positive, do not act on it)
---

Both verifiers returned SAFE TO MERGE, and they checked the load-bearing claims themselves rather than trusting the report: the 230,707-byte real save and a planted screenshot both provably survived a real mirror; the shortcut regression is closed twice over (env gate + baked -NoLaunchLock, both present in the on-disk deployed launcher, whose run-with-plugin.ps1 hashes identical to branch HEAD); FileShare.None exclusivity and the IOException catch were tested live; the tripwire was proven to hash CONTENT (a same-size edit is caught) and to throw rather than warn. Good work — this is a different artifact from what round 1 shipped.

Five items, then I merge. Nothing here is a data-loss risk.

## Do these

1. **MAJOR — the silent-success hole survives on the user's play path.** `check-game-windows.ps1` exits **3** when the game died between launch and check; `run-with-plugin.ps1:351` only throws on exit **1**. So exit 3 falls through, the launcher's catch never fires, the hidden pwsh exits 0, and the user gets: nothing on screen, no message box, no launch-error.log — the round-4 blocker's symptom verbatim. Reachable: scinject returns as soon as injection succeeds, then the game has ~2s to die on its own (partially-mirrored deploy tree, locked MPQ, second-instance self-exit). One line: throw on any non-zero, or treat 3 explicitly as "the game exited immediately after launch".

2. **MAJOR — the audio COM interfaces lack `[PreserveSig]`.** `EnumAudioEndpoints`, `GetCount`, `Item`, `Activate`, `GetSessionEnumerator`, `GetSession` are declared without it (unlike `GetProcessId`/`SetMute`/`GetMute`, which correctly have it), so the CLR consumes the HRESULT and THROWS on failure — every `if (... != 0) return false` / `continue` guard in `TryMuteProcess` is dead code. A verifier proved it: `Item(9999)` throws ArgumentException instead of returning a failure code. Failure mode: an endpoint invalidated mid-enumeration (USB headset unplugged, HDMI monitor sleeping — both device classes are on this machine and among StarCraft's three endpoints) throws out of the launch script after the game is already up. Add `[PreserveSig]` to those six, or wrap the enumeration.

3. **MINOR but same class — `-Sound` now calls into WASAPI on every USER launch, unguarded.** It changed from "skip muting" to actively calling `Set-ScProcessMuted -Mute $false`, after the game is up, with `$ErrorActionPreference='Stop'`. Any COM hiccup shows the user "failed to launch" over a StarCraft that is running fine. Wrap it and downgrade to a warning — audio bookkeeping must never fail a launch that already happened. (It also costs the user up to 5s of polling per launch; consider skipping the poll entirely on the unmute path.)

4. **MAJOR — guard misses `rm`/`del`/`rd`/`erase` (all Remove-Item aliases) and `Set-Item`/`si`.** A verifier ran a 23-case matrix: all 15 ordered cases pass, no read-only regression — but `rm 'HKCU:\SOFTWARE\Blizzard Entertainment' -Recurse -Force` returns PASS in worker mode. `rm` is the most natural spelling an agent reaches for, and it is the exact verb class of the original incident. Add them, and correct the residual-limits comment, which currently claims alias coverage.

5. **MAJOR (docs) — the tripwire watches 3 of the 5 preserved classes** (`characters`, `save`, `Maps\Replays`) but `maps\download\` and the root `SCScrnShot_*.pcx` — the two you added this round — are not snapshotted, while `deploy.ps1:38-40` and `README-deploy.md:34-35` both say the tripwire covers "those directories" after listing all five. Either extend the snapshot to all five (preferred; the mechanism already handles files-added-between-snapshots correctly) or make both doc sites state the real scope.

## Do NOT "fix" this one — it is a false positive I checked myself

A verifier reported that `run-with-plugin.ps1:103` and `README-deploy.md:248` cite an AGENTS.md rule that does not exist. Your citations are CORRECT. I committed that rule to main as `baaba37` ("hard rule - never write live user state"), it is rule 5, and rule numbering now runs to 6. The verifier read your worktree, which is based on `266a6db` — the commit immediately before it. **Merge or rebase onto current main** so your branch carries it, and leave the citations alone.

## Tracked follow-ups, not for this PR

- The lock gate misses explorer/verifier agents (`explorer-args.ps1` deliberately clears `AGENT_TASK`); one-line widening to `-or $env:EXPLORER_RUN_DIR` when someone is next in that file.
- deploy-vs-user-launch stays unserialised by construction (the user's launcher must never wait) — correct trade-off, now written down.
- "Does StarCraft's own session actually appear" remains open. Your report said so honestly; a verifier confirmed the mechanism works generically (3 endpoints walked, a real pid matched) so only that last link is untested. It does not gate the merge — worst case is a warning and an audible test run.
- `tools/plugin/README.md` has no Sound section and never documents `-Sound`, `-HudRow` or `-NoLaunchLock`, while `sc-audio-mute.ps1:9` points readers at it.
- `Get-FileHash` in the snapshot helper has no `-ErrorAction`; `SetMute`'s HRESULT is discarded so a failed mute still reports "sound muted".

Push, CI green, DONE per number. After merge I will run deploy.ps1 myself and tell the user their shortcut is live.
