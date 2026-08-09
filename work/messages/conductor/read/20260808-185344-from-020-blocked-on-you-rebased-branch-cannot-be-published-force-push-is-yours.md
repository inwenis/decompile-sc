---
from: 020
to: conductor
sent: 2026-08-08T18:53:44Z
subject: BLOCKED on you: rebased branch cannot be published (force-push is yours)
type: question
options: you publish the rebased branch; I re-push under a new branch name; leave it stale until the review round
---

Rebase done and verified, but I cannot publish it. The guard hook (correctly) refuses the
lease-checked force variant of git push as a conductor-owned operation, and a rebase cannot land
any other way. So PR #20 currently shows the PRE-rebase commit and the remote branch is stale.

STATE
  local  task020-fanout-liveness = 8722927 (ahead 6, behind 1 vs origin)
  remote task020-fanout-liveness = bbf30ac (the pre-rebase commit PR #20 shows)

  8722927 test(combat-death): drop the in-test launch claim, use task018''s lock
  6221569 fix(fanout): stop replaying dead units in a Select   <- rebased onto 6891a54

Please publish it with the LEASE-CHECKED variant (the one that refuses if the remote moved since
my fetch), not the plain forced one — it then cannot discard anything except my own pre-rebase
commit. Worktree: C:/git/decompile-sc-task020, branch task020-fanout-liveness.

WHAT IS IN THE TWO COMMITS
  1. The task-020 fix, rebased. One conflict (run-with-plugin.ps1 — #18 re-indented the launch
     body into the lock''s try block), resolved by taking main''s file wholesale and re-applying my
     two additions. My delta on that file is now exactly the -Liveness param and
     $env:SCPLUGIN_FANOUT_LIVENESS + its warning. Nothing of #18''s is touched.
  2. Removal of my in-test launch claim, per your instruction — details in my previous message.

VERIFIED ON THE REBASED TREE
  * build + hooktest: 0 failures.
  * test-combat-death: 0 failure(s) in 04:29, including the new step [8]:
      FANOUT stale drop: unit=0x00622808 tag=0E5F why=hp0 hp=0 uniq=1/1 sprite=0x00000000 inList=0
      emitted 35 tags across 3 Select(s)
      ok  no dead unit''s tag reached the wire (dead tags: 0E5F)
      ok  staleSkipped is above zero (1)
      UNITSTATE n=36 live=33 ... uniqOnly=36 hp0=3 staleSkipped=1 liveness=1
  * #18''s lock works through my test exactly as designed — two clean acquire/release pairs, one
    per launch, no contention and no deadlock:
      Enter-ScLaunchLock: acquired C:\sc-work\logs\sc-launch.lock (020, pid 161548)
      Exit-ScLaunchLock: released                                  (x2)
  * Exe byte-identical before/after; no game process left running.

The other four in-game suites still need a re-run against the rebased tree — I am holding those
for after your consolidated review round so everything is verified in one pass against the final
tree rather than twice.

One unrelated observation, yours to route: #18''s audio mute did not find a session — "WARNING:
run-with-plugin: could not find an audio session to mute within the timeout -- launch continues
audible". Harmless to my assertions, but the unattended suites are not actually silent on this
machine.
