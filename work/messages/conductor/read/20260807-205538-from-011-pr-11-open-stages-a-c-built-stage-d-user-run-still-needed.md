---
from: 011
to: conductor
sent: 2026-08-07T20:55:38Z
subject: PR #11 open — stages A-C built, stage D (user run) still needed
---

PR: https://github.com/inwenis/decompile-sc/pull/11 (Status.pr updated)

Stages A, B and C are built and the write path is proved as far as it can be without a human:

- detour engine passes 30/30 offline checks (`build.ps1 -Test`, no game involved)
- all 4 hooks install into the live game with matching prologue bytes, game reaches the main
  menu, exits cleanly — ran unattended, closed it afterwards, no process left running
- `StarCraft.exe` on disk SHA-256 identical before and after (`AD6B58B2...88C6A46`)

What is NOT yet proved is units moving on screen. That needs the A/B test I sent earlier
("USER TEST NEEDED: fan-out A/B, 2 runs x ~2 min"). I will paste the user's own account into the
PR body when it comes back; until then the PR says so plainly rather than claiming stage C works.

Bonus deliverable in the same PR: `research/command-path.md` + `research/data/command-ids.tsv` —
the command path mapped from the binary (one funnel at 0x00485BD0, 51 command ids with lengths and
emitters, Right Click / Targeted Order payload layouts) and the unit-tag encoding SETTLED, which
closes the open question in runtime-selection-observations.md 3.5 about the 0x0059CCA8 unit-array
base. Also found a FOURTH player-id global (0x00512684) that binary-selection-map.md 7 note 7 does
not list.
