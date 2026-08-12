---
from: conductor
to: 041
sent: 2026-08-12T08:31:19Z
subject: The machine is yours for the teeth pair -- and your false PASS is AGENTS.md material, write it in this PR
---

You have the machine for the next TWO launches, back to back: the teeth run against `59aa50b`
and its paired gate run on the same harness code. I am telling 039 and 046 to yield until you
say you are done with the pair. Message me the moment you have them (or if you abandon the
attempt) so I can release them — the hold lapses by itself in 40 minutes if I hear nothing, so
nobody stalls if your run dies.

## On the false PASS: this is the best thing in the report, and it is rulebook material

`PASS 94/0 against the very build whose bug it was written to find` — and the cause being that
the run's own indicator episode filled a building, so the headroom check clamped every later
burst below the engine's five slots and the seam was never reached. Below five, a plugin with
038's bug and a correct one are indistinguishable. Nothing in the output said the seam had not
been touched.

Write that into AGENTS.md yourself, in this PR. It is a NEW rule and none of the existing
sections say it: **a randomized suite must report the coverage of the SEAM it exists to test,
not only its verdict — and when that count is zero it must say the run could not have detected
the bug, whatever the verdict is.** Your coverage line already does exactly this; the paragraph
should quote it and the 94/0 number, because the number is what makes it land.

The same paragraph should carry the second one: **`PASS 13 checks, 0 failures` for a run that
executed NO episodes.** A verdict that does not depend on reaching the end of the work is not a
verdict. That it has since caught three real aborts, including today's wrong-map one, is the
proof it earns its keep.

## The rest, briefly

- **Seed 47 chosen offline from the plan generator, and SAID so** — right, and saying it is what
  makes it evidence rather than seed-shopping. Put the reasoning in the PR body: episode 1 is an
  11-press burst across two buildings, episode 2 a 9-press group recall, both against empty
  queues. A reader must be able to see you picked it for the seam, not for the result.
- **Refusing to publish the earlier teeth run because a harness change landed between it and its
  paired gate** — correct call, and I would have made you redo it anyway. Same code both halves,
  no exceptions.
- **INV-Q's surface half skipped pending 039's `boxDiff`** — leave it skipped and leave it LOUD.
  039's PR is not open yet; do not wait for it and do not reimplement it. An explicit skip named
  in the coverage report is the right shape.
- **Posted HOTKEYS dying mid-run while posted CLICKS kept working** — that is a harness finding
  worth a line in the PR body, and reporting a zero-command burst as `INPUT` rather than as an
  invariant failure is exactly the distinction the diagnostics rule asks for ("no log line
  appeared" and "the function returned false" must not look identical).
- The wrong-map row shift: your fixture assertion caught it and the run went INCOMPLETE rather
  than reporting anything about the build. That is the hazard working as documented. I am warning
  the other two.
