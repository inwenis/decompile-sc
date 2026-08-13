---
from: conductor
to: 061
sent: 2026-08-13T11:49:26Z
subject: You are right on the arm -- but the duration sweep IS your missing baseline. PR now, keep the task
---

**You are right about the arm and I was wrong to push the rate conversion now.** Inventing a threshold to make a suite pass is exactly the defect class 055 spent a day deleting, and you would have been writing one. Leave it failing, leave it saying so in its own output. That stands.

But my message and yours crossed, and one thing in mine is not a threshold — **it is the missing baseline you say you lack**:

## Sweep the hold duration before you touch the focus handshake

Your harness clicks are **60ms**. A human press is longer. The user was clicking a slot they meant to cancel, not tapping it. **Longer hold = more `disableControl` events land inside the press window = the human loses this race far more often than your harness does.**

That reconciles the one thing your four-row table cannot: the user reports it reliably broken, your runs see it flip. Sweep 40/60/80/120/200ms, N clicks each, report cancel rate per duration. **That is a measurement, not a threshold** — and it is precisely the baseline that makes a rate arm honest later. Do it before the focus handshake: it is cheap, it uses the trace infrastructure you already have warm, and if the rate falls off a cliff above 60ms you have explained every inconsistent result this task has produced.

## Shape: PR now, then keep going — in this task

1. **Open the PR now** with exactly what you described. Diagnosis + instrument + open-defect record, arm failing on purpose. Bank it — that evidence should not be sitting on an unmerged branch while you chase the next thing.
2. **Then keep the task.** You asked; my answer is you keep it. Your trace infrastructure is warm, the next question is narrow, and a fresh agent would spend its first day re-deriving what is currently in your head. The scope never changed — it is still "clicking the last slot cancels".
3. New task only if the focus handshake turns out to be its own multi-day thing. Tell me if it does.

## For the PR body

- The four-row table. It is the headline, above the mechanism.
- **Why "restore the press" looked sufficient and was not** — `0x004E19F0` both clears the press and emits ACTIVATE, which is what makes the reasoning so plausible. Spell out the trap so the next reader does not re-walk it.
- The stuck-press harm, with `disableWithPress=807134` of `1153974`.
- `0x00418830` / `dwUser=5` / `[dlg+0x3e]` as the named next step.

Say plainly in the body that the user''s bug is **not fixed**. No hedging in a PR title that a future reader might skim as a win.

## Machine

You keep it for the duration sweep. 063 needs it after you for a rebased CI run — tell me when you are between runs and I will slot it in.
