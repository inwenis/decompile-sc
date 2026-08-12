---
from: conductor
to: user
sent: 2026-08-12T22:34:19Z
subject: Skills deployed and loaded -- but deploy.sh makes COPIES on Windows while printing "Linked", issue #24
---

**Pulled, deployed, and the skill is live — no hand-fix needed.** But the deploy does work wrongly, in a quiet way, so: **https://github.com/inwenis/skills/issues/24**

## What worked

`C:/git/skills` fast-forwarded 25 commits to `1e58b56`, clean tree. `bash deploy.sh` linked all seven skills into both agent directories, and Claude Code now loads them — `architecture-delta-review` and `verify-first` included. Your `conductor` and `conductor-onboard` were untouched: I checked for name collisions before running, because that script deletes whatever non-symlink sits at a target path, and those two are real directories.

## What is wrong with it

It prints `Linked: architecture-delta-review -> /c/Users/inwen/.claude/skills/...` and then creates a **copy**:

    test -L ~/.claude/skills/architecture-delta-review   ->  NOT A SYMLINK
    Get-Item ... | LinkType                              ->  (empty, not a reparse point)
    SKILL.md hash deployed == hash in repo               ->  content copy

MSYS/Git Bash implements `ln -s` as a copy unless `MSYS=winsymlinks:nativestrict` is set **and** Developer Mode is on. It returns 0 either way, so `set -euo pipefail` cannot catch it.

The consequence is not that skills are broken — they work fine right now. It is that **your next `git pull` in the skills repo will silently change nothing for any agent**, and a stale copy is indistinguishable from a live link. The success message asserts a relationship that does not exist, which is worse than saying nothing, because nobody re-checks something that said `Linked:`.

That is the same shape as the bug the current HEAD commit fixed — deployed to Amp only, invisible to Claude Code, no error. Reported success, wrong outcome.

The issue suggests verifying with `test -L` after each link and failing loudly, setting the MSYS flag, and an honest fallback message when a real symlink is not achievable.

**Practical note until you perma-fix it: re-run `bash deploy.sh` after every pull of the skills repo.**

## A small thing worth knowing about your guard hook

My first attempt to send you this message was BLOCKED by `guard-destructive.ps1`, because the body quoted a Windows link command whose switch it read as a system path being deleted. Nothing was at risk — it was prose in a message file. Worth a look at some point: a guard that inspects message TEXT for destructive patterns will keep firing on any message that discusses one, which is most postmortems.

## Next

`architecture-delta-review` is now available to me directly, so recurring reviews will run through your skill rather than my hand-written brief. Task 052 is still doing the one-off baseline pass — that has to exist before a *delta* review has anything to be a delta against.
