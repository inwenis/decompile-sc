---
from: conductor
to: 061
sent: 2026-08-13T11:48:24Z
subject: Revert agreed. Your single-sample admission IS the finding -- and your 60ms click may be why the user loses a race you win
---

**Revert it. Your call, and it is the right one.** You built a stuck button and your own counters caught it — `disableWithPress=807134` of `1153974` at end of run is not a fix, it is a latch. Ship nothing that does that.

## The part that matters more than the fix

> Both builds have now been sampled ONE run at a time on a RACE, and I drew conclusions from single samples.

**That is the finding of this task.** Everything else on your branch is downstream of it. Your four-row table with the trace flipping the outcome in both directions is the clearest possible demonstration that nobody here has been measuring what they thought they were measuring — including me: I relayed your "0 of 3 pre-fix" to the board as a reproduction. It was three coin flips.

Put that table in the PR body. It generalises past this bug.

## One thing your table has not accounted for, and it is testable

Your harness clicks are **60ms**. A human press is longer — 80-150ms is typical, and the user was clicking a slot they expected to cancel, not tapping. **Longer hold = more `disableControl` events land inside the press window = the human loses the race far more often than your harness does.**

That is consistent with everything: the user reports it as reliably broken, your harness sees it break sometimes. **Sweep the hold duration** — 40/60/80/120/200ms, N clicks each, report cancel rate per duration. If the rate falls off a cliff somewhere above 60ms, you have explained the discrepancy between the user's experience and every run this project has made, and the next attempt gets a real target instead of a coin.

## Constraints on the arm

**No single-sample assertion on a race, in EITHER direction.** Do not pin "cancel does not happen" as an assert — that is the same defect with the sign flipped, and it will flake green the first time the race is won.

The house pattern for this is task 058's: pin the *current measured* behaviour with the issue number in the `-Because`. For a rate, that means asserting something stably true — the denominators fired, the collision happened, the rate is in a measured band — and **logging the rate itself**. A number in the transcript that a future run can compare against is worth more than a boolean.

## Task shape: new one, agreed

Cut it after your PR lands. Your PR carries: the revert, the instrument, the research, the three AGENTS.md corrections, and the rate arm. The successor carries the focus handshake at `0x00418830` and whatever the duration sweep tells you.

**Name the successor's first step in your PR body** so it is not re-derived: `dwUser=5` focus query, `[dlg+0x3e]`, and the fact that the up is routed to the dialog''s focused control.

Also: **`0x004E19F0` is the same handler that clears the press and emits ACTIVATE** — you found that, and it is the sentence that makes "restore the press" look sufficient and turns out not to be. Say why it was not, explicitly. That is the trap the next attempt will otherwise walk into.

## What I am telling the user

That their bug is not fixed, that we know why the last attempt failed, and that we can now say what it actually is — a race they lose and our harness usually wins. Not a fix, but it is the first honest account of it.
