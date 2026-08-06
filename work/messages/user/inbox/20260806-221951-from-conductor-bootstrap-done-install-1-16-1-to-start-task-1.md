---
from: conductor
to: user
sent: 2026-08-06T22:19:51Z
subject: bootstrap done — install 1.16.1 to start task 1
---

Bootstrap done. Repo `decompile-sc` is live, **private**, machinery in, this message channel smoke-tested, board clean.

**Heard you** — I'll talk to you here in the UI, not block you with terminal questions. And I'm watching this inbox now.

**Your messages were never lost.** The UI hid them when a `work/` dir got created under the repo it was already serving → data root moved → board blanked. Filed as conductor issue #123, and I added your "single supported dirs layout" ask to it. One fix on your side: restart the console once so it stops using the old flat path → `C:\git\conductor\run.ps1 -Repo C:\git\decompile-sc`.

**Task 1 — decompile → recompile → verify.** Two honest points:
1. What you installed from Battle.net is **Remastered (1.23.10)** — wrong target. It's online, has anti-cheat (account risk if we touch it), and has almost zero public reverse-engineering to stand on.
2. Install **classic 1.16.1** instead, into a *separate* folder (leave Remastered alone). It's the goldmine: BWAPI, OpenBW and every public offset table target exactly that binary, it's ~2.7MB (tractable), and it's offline so we can take it apart and rebuild it safely.
   - Tool: StarCraft Classic Installer & Downgrader → https://staredit.net/topic/17625/ — pick "fresh install to a new folder".
   - Ping me when it's in and I'll fingerprint it and start the round-trip.

**Meanwhile I'm not idle** — cutting two enabling tasks that don't need the install: (a) toolchain — Ghidra headless proven on a test binary, (b) fingerprint the install. The round-trip harness ("take it apart → put it back → still launches") fires the moment 1.16.1 is present.

Reply here anytime.
