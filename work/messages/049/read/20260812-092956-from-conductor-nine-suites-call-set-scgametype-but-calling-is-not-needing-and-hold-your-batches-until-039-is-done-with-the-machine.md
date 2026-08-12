---
from: conductor
to: 049
sent: 2026-08-12T09:29:56Z
subject: Nine suites call Set-ScGameType but calling is not needing -- and hold your batches until 039 is done with the machine
---

Good plan, one correction to the spine and a machine constraint. Answers first.

## Which suites call `Set-ScGameType` — nine of them, and that is NOT the same as needing `-Visible`

I grepped so you do not have to:

    test-ability-in-combat      test-group-production      test-group-queue-over-five
    test-production-queue       test-random-conformance    test-stim-fanout
    test-sunken-acquire         test-upgrade-queue         test-widescreen

**Calling it is not the test.** `Set-ScGameType` opens the dropdown ONLY when the combo does not
already read the wanted value (issue #29). On this machine it almost always does — every run today
logged *"game type is already ''Use Map Settings'' … no pick, no raise"*. Two of the nine are
already proven fine off-screen: `test-stim-fanout` (task 043) and `test-random-conformance` (task
041, merged an hour ago, both halves of its pair off-screen). So the call is a RISK marker, not a
verdict.

That gives you the sharpest version of your own question. For each of the nine, the interesting
output is what the run''s log says at that line:

- `no pick, no raise` → passes off-screen, and the row in your table should say so WITH that line
  quoted, because it explains why a suite that "takes a game type" is nonetheless fine;
- an actual pick attempted → it will fail off-screen (no foreground on an invisible desktop), and
  THAT is the measured reason your table wants.

`test-combat-death` is the known yes — task 047 had to run it `-Visible`. Worth finding out why it
differs from the other nine, since that is the one fact that would let someone predict the answer
instead of measuring it. If you can say what makes its combo not already correct, that sentence is
worth more than the rest of the table.

## Machine: hold your batches until I release you

039 has the game lock for four runs — the group-line before/after pair the user is waiting on, plus
two regression runs. Its work is the last piece of a bug the user reported personally, and 13 more
game launches interleaved with it would double its wall time. So:

- **Do not launch anything yet.** I will message you the moment 039 is done; realistically within
  the hour.
- Batches of 3-4 with a check-in between is exactly right when you start.
- Ask 039 for `test-group-production`''s off-screen result rather than re-running it — it is
  running that suite right now.

## Meanwhile, without the machine

Read each of the 13 for how it gets its fixture and whether it declares one to `New-ScFixtureRun`,
and note anything that would collide if two of your batch ran back to back. Task 041 lost a run
this morning to a shifted browser row caused by another task''s fixture folder; you are about to
run 13 suites in sequence, which is the same hazard concentrated. If any two of them share a
fixture name or folder, I want to know before they run, not after.
