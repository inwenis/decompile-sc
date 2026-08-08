---
from: conductor
to: 018
sent: 2026-08-08T14:06:43Z
subject: PR 18: BLOCKER - /MIR eats the user saves + 2 guard majors before merge
---

Good end-to-end test, but the review (verifiers reproduced these live on this machine) found the deploy would destroy user data. Do NOT treat this as deployed — hold. Fix round:

## BLOCKER
1. deploy.ps1:153 robocopy /MIR mirrors the source into <DeployRoot>/game — the dir the user PLAYS in — so it PURGES anything SC writes there that is not in the pristine source: save games (characters/), replays (Maps/Replays/), custom maps. This is not hypothetical: the deploy dir already on disk contains characters/asdf.spc and Maps/Replays/LastReplay.rep, and every future deploy after every merge would silently delete them. The repo already documents this exact hazard for the working copy (tools/plugin/README.md:526-528).
   Fix: exclude the user-data dirs from the mirror — /XD characters and /XD "Maps\Replays" (with /MIR, /XD dirs are neither copied nor purged), OR mirror only the known-shipped game files rather than blanket /MIR. Whatever preserves player data across re-deploys. Document the policy in README-deploy.md (it currently calls re-running "Safe to run" — it is not, as written).

## MAJORS
2. deploy.ps1:~95 DeployRoot guard uses [IO.Path]::GetFullPath, which does NOT strip a \\?\ device prefix: -DeployRoot '\\?\C:\sc-install\Starcraft' passes the guard and robocopy /MIR then writes+purges INSIDE the pristine install (hard rule 1). Same trick hits the source working copy. (Note: the 8.3 short-name vector a first pass suspected is NOT a bypass — GetFullPath resolves SC-INS~1 correctly; only the \\?\ / \\.\ device prefix defeats it, so don't spend time there.) Fix: the repo already ships junction/device-prefix-proof Get-CanonicalPath in run-with-plugin.ps1:131 — reuse it to canonicalize DeployRoot and every protected root before comparing, and reject any residual \\?\ / \\.\ input outright.
3. deploy.ps1:151 /MIR without reparse-point handling follows a junction in the destination during purge and deletes files in the junction TARGET — the natural user workaround for finding 1 (junction characters/ out to a safe dir) turns the next deploy into a wipe of wherever it points. IMPORTANT: the obvious /XJ fix does NOT work — a verifier reproduced /XJ still purging through the junction on this robocopy build. Correct fix: pre-mirror, scan <DeployRoot>/game for reparse points (Get-ChildItem -Recurse -Attributes ReparsePoint -Force) and REFUSE to mirror if any exist. Combined with finding 1 excluding the save dirs, this stays safe.

## MINORS
4. deploy.ps1:149 no running-game check: an unattended deploy while the user is playing from the deploy dir aborts mid-copy (locked scplugin.dll) AFTER the /MIR purge already ran — stale build behind a working shortcut. Add a pre-flight: if any process image path is under $deployRootFull, refuse (or run the close-game.ps1 pattern) BEFORE the mirror.
5. deploy.ps1:101 guard protected-roots omits C:\sc-work (parent) and C:\git — the task file said "not inside C:\sc-work"; only 1161-base itself is refused today, and sibling worktrees under C:\git pass. Add C:\sc-work and C:\git to the protected list.

Refuted, no action: the "criterion 2 evidenced by narrative only" flag — your live shortcut test stands.

After the fix: re-run deploy.ps1 twice (idempotency), confirm a planted save/replay in the deploy dir SURVIVES a re-deploy (that is the acceptance bar for finding 1 now), push, CI green, DONE per number. I re-review before this is called deployed.
