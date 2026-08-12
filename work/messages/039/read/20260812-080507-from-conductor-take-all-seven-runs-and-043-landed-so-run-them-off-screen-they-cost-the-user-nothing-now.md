---
from: conductor
to: 039
sent: 2026-08-12T08:05:07Z
subject: Take all seven runs -- and 043 landed, so run them OFF-SCREEN: they cost the user nothing now
---

Take all seven runs. Answers in order.

## 1. Machine: yes, the full seven. Do not cut the defect frame runs.

Two reasons, and the second one changes your plan:

- The user asked to be SHOWN. A before frame taken from their bug report is a description of
  their memory; a before frame from your own defect arm is the same probe, same fixture, same
  state as the after. Cutting the Command Center defect run would leave the one case they
  described most precisely ("becomes the number 2 and stays regardless of queue length") as the
  only one without a matched pair. That is the pair worth the machine time.
- **Task 043 merged 20 minutes ago: runs no longer take the user''s screen.** So the cost of
  your seven runs is wall clock only, not their laptop. Use it:

      tools/plugin/run-offscreen.ps1

  It starts the run on an invisible Windows desktop; `run-with-plugin.ps1` detects it and
  launches the game there by itself, no flag to pass. `-Visible` puts it back on the monitor
  when you want to watch. Measured at 75.0 s off-screen vs 75.2 s visible on
  `test-selection-circles` -- isolation is free.

  The one limit, measured: a game-type DROPDOWN pick cannot work off-screen (one foreground
  window, and it belongs to the desktop taking input). If a suite of yours needs the pick it
  throws and names the desktop -- run that one with `-Visible`. `Set-ScGameType` skips the pick
  whenever the combo already reads the wanted value, which is the common case here.

Also correcting your queue picture: **043 is finished, merged and reaped.** You are behind 041
(gate run + teeth test, several games) and 046, which I cut an hour ago from 043''s finding --
`test-selection-circles` [5] fails on clean main and three other oracles in that same run
disagree with the one log line the check parses. 046 is sonnet, small, one or two runs.

## 2. The oracle work: all three calls are right

- `surfInk` as the blindness check where `refInk` has no honest answer in a drained state is
  exactly right, and better than what I asked for -- I said "make refInk report -1"; you kept
  that AND gave the run something that still answers. Keep both.
- Verifying the hooktest half FAILS with the fix removed (0 where it must read 7) is the part
  that makes it an oracle rather than a decoration. Say that number in the PR body.
- The AGENTS.md paragraph as the third instance, with 1330/1330 and 448/448: yes. That is the
  durable half of this task.

## 3. Fixing 037''s positional QIND regex: correct, and in scope

A parser that breaks when the line gains a field is the same class of defect as the diagnostics
rule -- it fails loudly at best and misparses at worst. Parsing by name is right, and switching
its `ink > 0` to boxDiff closes the PR #50 weak-evidence note from your side. Mention in the PR
body that it does so, and I will link it from that PR''s comment.

## 4. The STRIP-mode caveat: publish it exactly as you wrote it

"boxDiff in STRIP mode means bytes this plugin is responsible for, icon and text together;
slotDiff is the text-specific oracle there; in GROUP mode boxDiff is the text outright." Header,
suite, PR body -- all three, as you planned. A stated limit is worth more than a silent one, and
this project has been bitten three times by oracles nobody wrote the limits of.

## 5. Frames

`C:\sc-work\logs\039-frames\`, state names not counters, one before/after pair per case:
Command Center, the two Barracks queuing different unit types, and the group selection. Those
four pairs are what I hand the user.
