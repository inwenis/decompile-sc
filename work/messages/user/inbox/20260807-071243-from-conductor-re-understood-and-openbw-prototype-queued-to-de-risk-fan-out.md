---
from: conductor
to: user
sent: 2026-08-07T07:12:43Z
subject: re: understood - and OpenBW prototype queued to de-risk fan-out
---

Understood, and the merge relaxation is genuinely useful — exploratory branches can now sit open until they prove themselves, instead of me either merging something uncertain or throwing it away. That is also how the conductor system handles bake-offs, so it fits.

Plan stays:

  008  toolchain + our code in the game + READ selection state   <- running now
  009  intercept selection input, plugin-side list of any size
  010  fan out orders into <=12-unit chunks -> you play it
  then candidates 2 (wide visible selection) and 3 (full relocation)

## One thing I want to do IN PARALLEL, because it de-risks fan-out itself

The recon flagged the real risk in fan-out, and it is not the chunking — it is order semantics that depend on the WHOLE selection rather than on individual units. Archon merge, unload-all, and similar cases may behave differently when one player intent arrives as several 12-unit commands instead of one. We will not discover that from reading the binary; we discover it by running it.

Candidate #4 from the research is exactly the cheap way to find out: prototype the raised cap in OpenBW, a separate open-source reimplementation. No game hooking, no binary patching, near-zero risk, and it tells us which orders misbehave BEFORE we write the hooks. That is de-risking the thing we are building now, not jumping ahead to 2 and 3.

I am holding it briefly rather than starting it immediately: task 008 is installing a C++ toolchain right now, and an OpenBW build needs its own. I do not want two workers racing on compiler installs. The moment 008's toolchain lands I will cut it to run alongside 009.

## Status right now

008 is working. Long task — a real compiler install, then the injection vector, then the runtime read. Your pristine install is still hash-verified unchanged. Nothing needs you.

The thing I am watching hardest: whether the addresses we mapped statically hold in a LIVE process. That answer decides how smoothly 009 and 010 go, and finding a bad mapping during a read costs nothing.
