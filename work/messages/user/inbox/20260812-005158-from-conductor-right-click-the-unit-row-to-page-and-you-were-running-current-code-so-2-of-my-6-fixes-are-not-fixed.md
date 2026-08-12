---
from: conductor
to: user
sent: 2026-08-12T00:51:58Z
subject: Right-click the unit row to page. And: you were running current code, so 2 of my 6 "fixes" are not fixed
---

# Your paging question, answered now — plus four workers on the rest

## 1. How to cycle through units when you select more than 12

**Right-click on the unit row** (the 12 portraits at the bottom). Each
right-click flips to the next page; it wraps around. It only responds when
you have more than 12 selected — with 12 or fewer there is nothing to flip to.

That shipped with the `page i/j` indicator and nobody ever told you the
gesture. My fault, not yours.

## 2. The bad news first: you were running current code

I checked before dispatching anything. Your deployed plugin is stamped
`2026-08-11 12:15:47` — built *after* every merge I claimed this morning.
So this is not a stale shortcut. Two things I reported as fixed are not
fixed on your screen:

| I told you | you found |
| --- | --- |
| "the queue is shown" for upgrades | nothing on a Terran Engineering Bay |
| "the 5th icon fills, and a +N appears" | a stuck "2", a blacked-out slot, a blue flash |

That means our tests are passing while the screen is wrong — the same trap
that hid the page indicator for weeks. Every task below is required to prove
its fix with a captured frame from a real game, and to write a test that
*fails on today's code first*. A test that could not have caught the bug is
not a regression test.

Two of the six did hold up: you said multi-building selection and control
groups "work nicely", and that matches what we shipped.

## 3. What is running right now

| # | task | what it chases |
| --- | --- | --- |
| 037 | `upgrade-queue-visibility` | why the upgrade queue is invisible on an Engineering Bay, and which buildings ever showed it |
| 038 | `group-queue-over-five` | queueing past 5 when several buildings are selected — including that it *charges* you for what it queues |
| 039 | `queue-indicator-corruption` | the "2"/blackout/blue-flash 5th slot, and the queue text hiding behind the icon row |
| 040 | `test-host-isolation` | your VM question |

Three different renderings from three different buildings, one of them a
literal "2", is usually one bug wearing three masks — 039 is told to find the
shared cause before fixing anything.

## 4. The VM — task 040, and the one rule I put on it

Yes, worth doing, and it is being investigated properly rather than
enthusiastically. The honest complication: your machine is **Windows 11
Home**, which does not offer Hyper-V — the answer most people reach for is
off the table, so the alternatives (VirtualBox, a second Windows session,
others) get measured on setup cost, run-time cost, and whether frame capture
still works. A route that runs the game but breaks our screenshots is not a
route, because looking at frames is our entire verification method.

**It installs nothing on your machine without you saying yes first.** It
reports what it would install, where, and what it costs; you decide.

## 5. Your randomized-testing idea is queued next, and it is the right instinct

"list all the actions like building x then scheduled unit a then 12 times and
we verify that it build 12 units and charged for 12" — that is exactly the
test that would have caught section 2 above, because it asserts the engine's
own result instead of asking our plugin what our plugin did. It goes out as
soon as a worker frees up; I am holding at four so they are not all queueing
behind each other for the one machine that can run the game.

## 6. Board

- 4 running, 0 open PRs, 1 queued (the randomized tests).
- GitHub Actions billing is still the one thing only you can fix. Local
  checks have covered every merge in the meantime.
- Nothing needs a decision from you right now. The VM approval will, later.
