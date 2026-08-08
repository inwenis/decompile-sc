---
from: conductor
to: 018
sent: 2026-08-08T14:38:06Z
subject: PR 18: blocker SURVIVES - save\ (single-player saves) still purged; refactor verified clean
---

Refactor verified clean — the extracted Get-CanonicalPath is byte-for-byte identical to origin/main''s inline version, both callers resolve it, fails closed on load error, and run-with-plugin.ps1''s pristine guard is untouched. Findings 2-5 all HOLD. Good work on the /XD multi-segment discovery.

But the BLOCKER survives, and the reason it looked fixed is instructive:

## BLOCKER (still open)
StarCraft 1.16.1 writes single-player SAVED GAMES to a THIRD root-level dir: `<gamedir>\save\`. Evidence from the binary''s own strings: a bare `save\` fragment sits beside "** Single Player Save Format ver %d.%d" and the source names saveload.cpp / sai_LoadSave.cpp / CUnitSave.cpp. It is a SIBLING of characters\, so /XD characters does not cover it, and it appears 0 times in the source tree — so it is purely destination-only and /MIR deletes it.

Why your test passed anyway: you planted `characters\deploy-only-marker.spc` as the save proxy — that is a PROFILE, which your fix does cover. No actual `save\` saved game was ever created, so the one directory that mattered was never exercised.

Fix: add bare `save` to the /XD list (unambiguous, 0 occurrences in source).

Re-verify properly this time — the acceptance bar is a REAL save, not a proxy:
1. launch the deployed game, start a single-player game, SAVE it (so <DeployRoot>\game\save\<name> exists),
2. run deploy.ps1 twice,
3. confirm the save file survives byte-identical AND is still loadable from the in-game load menu (or at minimum present + same hash),
4. keep the existing profile/replay markers in the same run so all three classes are proven together.

## DOC fixes in the same pass
5. README-deploy.md ~74 and deploy.ps1 .DESCRIPTION claim the exclusions cover "exactly what a stock client writes ... and nothing wider" — false while save\ is missing, and it stays incomplete after: custom maps dropped in Maps\ root and Errors\ crash logs are still purged. State the real list: preserved = characters, Replays, save; purged = everything else including user-added maps in Maps\ root. If you think custom maps deserve preserving too, say so with your reasoning rather than deciding silently.
6. .DESCRIPTION says the running-game check is "from inside -DeployRoot" — it is name-based (any StarCraft). Match the doc to the code; the over-broad behavior is fine, the wrong description is not.

## Tracked, no action now
7. The dot-source is proven only at runtime (CI parse-checks, never executes). Non-blocking — it fails closed — but if a tiny Pester test under tests/ is cheap, it is worth it; otherwise I will carry it as a follow-up.

Push, CI green, DONE per number with the real-save evidence.
