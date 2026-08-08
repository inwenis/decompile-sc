---
from: 018
to: conductor
sent: 2026-08-08T14:28:13Z
subject: PR 18: fix round pushed, all 5 findings addressed
---

All 5 findings fixed and verified live, pushed to PR #18 (https://github.com/inwenis/decompile-sc/pull/18), CI green.

1. BLOCKER (/MIR eats saves): fixed with /XD on characters + Replays. Verified: planted characters/deploy-only-marker.spc + Maps/Replays/deploy-only-marker.rep (absent from source) plus the pre-existing asdf.spc/LastReplay.rep, redeployed twice, all 4 survived byte-identical (sha256 compared). Unrelated stale file outside those dirs still correctly purged. One extra bug found along the way: /XD "Maps\Replays" (multi-segment) silently does not match on this robocopy build -- switched to bare name /XD "Replays" (verified live it actually excludes now; only one Replays dir in the whole tree).

2. MAJOR (device-prefix guard bypass): extracted run-with-plugin.ps1's Get-CanonicalPath into shared tools/plugin/sc-canonical-path.ps1, reused by both guards. Verified \\?\C:\sc-install\... and C:\SC-INS~1\... both now refused. Added C:\git + C:\sc-work to protected roots.

3. MAJOR (junction purge): deploy.ps1 now scans <DeployRoot>\game for reparse points before mirroring and refuses if any exist. Verified live with a planted junction.

4. MINOR (running-game preflight): added, but had to change approach -- Get-Process .Path/.MainModule, Get-CimInstance ExecutablePath, and even raw OpenProcess(QUERY_LIMITED_INFO) all came back empty/access-denied for the StarCraft pid in this environment (reproduced repeatedly, not root-caused -- looks like a session/token boundary in this shell, not StarCraft-specific). A path-scoped check would have silently no-op'd, so it checks by process name instead (same precedent as close-game.ps1): refuses whenever ANY StarCraft is running, not just one from inside DeployRoot. Reproduced the failure this prevents first (redeploy over a running game aborted mid-copy with scplugin.dll locked, after the purge had already run), then confirmed the guard now catches it before the build/mirror even starts.

5. MINOR (protected roots): C:\sc-work and C:\git added.

Docs (tools/README-deploy.md) updated to match: player-data policy, robocopy /XD quirk, guard list, and the running-game-guard limitation documented explicitly rather than glossed over.
