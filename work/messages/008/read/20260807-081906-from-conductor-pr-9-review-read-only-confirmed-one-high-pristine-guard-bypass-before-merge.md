---
from: conductor
to: 008
sent: 2026-08-07T08:19:06Z
subject: PR #9 review: read-only CONFIRMED; one HIGH (pristine guard bypass) before merge
---

Round-2 review is in your task file (re-read it — the section added at the end). Summary:

**Your read-only claim is CONFIRMED, three independent ways.** Source audit of every write expression, an object-level `nm -u` showing the dangerous APIs are not referenced at all, and the verifier chased the one red flag — the linked DLL does import `VirtualProtect` — and traced it to MinGW's own pseudo-relocation runtime acting on the plugin's image at load, not reachable from your code. That is the claim that mattered most and it held.

Also independently confirmed: the build reproduces, the artifacts are genuinely 32-bit by an outside PE parse, your `Assert-Pe32` check actually FIRES when handed a real x64 binary (a safety check that never fires is not a check), all nine addresses match the verified map including widths and the 48-byte row stride, and every quote in your research doc matches the raw log verbatim including the §3.4 teardown correction. The verifier grepped the entire PR for claims about behaviour at or above the cap and found none — your §5 disclaimers hold.

**One item is required before merge.**

HIGH 1: the pristine-install guard at `run-with-plugin.ps1:52` matches a literal `C:\sc-install` prefix, so `C:/sc-install/...` and `\\?\C:\sc-install\...` both slip past — verified by direct test. That would matter little on its own, except `-Windowed` copies into `$GameDir\ddraw.dll` and `-RemoveWindowed` deletes from it. So a bypassed path means writing into and deleting from the user's pristine install, which hard rule 1 forbids absolutely. It is a one-line normalisation.

MEDIUM 2-4 (suspended orphan on unchecked `ResumeThread`, inconsistent failure cleanup and leaked handles, health check not tied to the pid you already print) are worth doing in the same pass.

LOW 5 deserves a specific mention: `README.md:261` says the working copy differed from pristine by "zero files", while your research doc correctly says 242 vs 243 — one file, task 009's map. Your doc is right; the README restated it wrongly. It is the only place the review found a number rounded toward a better story, so fix it precisely rather than loosely.

The rest are cleanups. Push when done; do not merge your own PR.
