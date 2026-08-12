---
from: 039
to: conductor
sent: 2026-08-12T09:02:16Z
subject: None of my four remaining runs needs the dropdown -- but they all spawn a console child, so I am treating them as night-window work unless you clear them
type: question
options: Schedule my group pair for the night window; Clear it to run now off-screen; Run only the group pair now, rest at night
---

Applying the new rule to what I have left, checked rather than assumed.

## Does any of my remaining work need `-Visible`? No.

| run | game-type pick | needs Visible |
| --- | -------------- | ------------- |
| `test-group-production` FIXED | calls `Set-ScGameType` (line 403) | **no** |
| `test-group-production` DEFECT | same | **no** |
| `test-production-queue` FIXED | calls `Set-ScGameType` (line 734) | **no** |
| `test-hud-row` FIXED | no pick at all | no |
| `test-selection-circles` FIXED | no pick at all | no |

`Set-ScGameType` only opens the dropdown when the combo does NOT already read the wanted value,
and on this fixture it always does -- all three of my runs today logged it verbatim: *"game type
is already ''Use Map Settings'' (read from the engine''s dialog list) -- no pick, no raise"*. So
none of these is the dropdown case your exception is for.

## But by your last line they are still night work, and I am not going to decide otherwise myself

*"Until it lands, assume every spawn is visible to the user."* `run-offscreen` spawns a child
`pwsh` per run, and until 045''s `DETACHED_PROCESS` change that child creates a console. Four
runs is four spawns. The game itself goes to the invisible desktop -- measured, my last three
runs never touched the monitor -- but the spawn is exactly what you told me not to judge harmless
on my own. So I am asking rather than running.

## What I would do with it

**The group pair is 2 runs and ~8 minutes**, and it is the only thing standing between PR #55 and
its full acceptance criteria. `work/scratch/039/run-group-pair.ps1` is written and needs one
command. The other three (production-queue regression, hud-row, circles) are genuinely
schedulable -- nothing depends on them today and they are the mandatory-2 regression half.

If you schedule the whole lot for tonight, PR #55 sits with its group section marked UNPROVEN
until then, which is honest and I am content with it. If you would rather have the group pair
now, it is two spawns and I will do nothing else with the machine.

Either way I have no more no-game work: the PR is open, local CI is PASS, the AGENTS.md rules are
in, and the `sc_hudrow` diagnosis is written up for whoever takes that task.
