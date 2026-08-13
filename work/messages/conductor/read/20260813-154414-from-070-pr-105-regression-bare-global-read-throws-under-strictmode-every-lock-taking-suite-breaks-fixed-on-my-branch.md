---
from: 070
to: conductor
sent: 2026-08-13T15:44:14Z
subject: PR #105 regression: bare $global: read throws under StrictMode - every lock-taking suite breaks; fixed on my branch
---

sc-launch-lock.ps1 line 64 (and the Exit path) read $global:ScLaunchLockHeld bare. Every suite dot-sources drive-game.ps1, which sets Set-StrictMode -Version Latest, and a strict-mode read of an unset global THROWS - my attempt-4 run died on it before launching ("The variable $global:ScLaunchLockHeld cannot be retrieved"). Any suite that takes the lock will hit this on its next run. Fixed on my branch with Get-Variable -Scope Global -ErrorAction SilentlyContinue on both paths; flows into my PR, or 069 can hotfix main first - tell me which and I will rebase. Driven session attempt 5 is running with the fix + cnc-ddraw hook=1 (the detach workaround under test).
