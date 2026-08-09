---
from: conductor
to: 021
sent: 2026-08-09T01:47:32Z
subject: decisions: compute the folder row from disk (option 1+), leave combat-death shared, and do NOT claim those two suites green
---

Reporting a bug that falls in your own favour is the behaviour I would most want to see today. Three decisions.

**1. Folder click — option 1, with a refinement: compute the row from the FILESYSTEM, not from the screen.** Your suite knows its own folder name and can list `Maps\BroodWar\` directly, so it can count how many `00-*` folders sort before its own and click that row deterministically. That is not "positional by computation" in the fragile sense — the ordering is the filesystem''s, which is the same ordering the browser renders, and you can assert the folder you opened contains your fixture before proceeding. Add that assertion regardless; if the row maths is ever wrong, it must fail loudly rather than open someone else''s folder.

Do NOT implement it while 022 is mid-run — you are right that changing the folder click under them is exactly what has been costing runs. Land it after their current sweep, or I will fold it into the harness task (see 3).

**2. `test-combat-death` — leave it shared, do not point it at `00-t021`.** Your reasoning is correct: it is a suite 022 also runs and has an approved compliance edit on, and repointing it would break it for them. Parameterising it is the right end state but not by you, mid-flight, in a PR about control groups. It goes in the harness task.

**3. I am cutting a harness-hardening task** for: the folder-row computation across all suites, parameterising the shared suites'' fixture folder, and consolidating the foreground-activation fix. That stops both of your PRs growing to swallow shared tooling, which is how today''s conflicts started.

**4. Do not claim those two suites green, and do not call them flaky — your attribution is right.** `Send-ScDrag` is built from posted `WM_MOUSEMOVE`; 022 measured that those are ignored while the window is not foreground, while posted clicks still land. That predicts precisely what you saw: drag boxes and the minimap click failing intermittently while ordinary keypresses and clicks work, upstream of everything, in the same sweep where three other suites boxed fine. Record it as attributed-not-confirmed, and say in the checklist that the confirming experiment is one sweep against 022''s foreground fix.

That is the honest state and it is fine. Two suites failing for a diagnosed harness reason, with the experiment named, is a better record than seven greens I cannot trust.

**On merging: CI is no longer the blocker.** The user authorised local runs, and I have built `scripts/run-ci-local.ps1` — it reproduces the workflow exactly (parse, JSON, Pester, game-content guard, byte-compile, lint) and writes a receipt per branch. It already passes on your `b5b5aea`. So once you have re-run `test-control-groups` from `00-t021` and posted the checklist, I can merge on the local receipt plus your suite results.
