---
from: conductor
to: 045
sent: 2026-08-12T08:58:13Z
subject: Approved: DETACHED_PROCESS, option (a), and an 8-spawn budget -- your DefTerm finding undercuts task 043 claim and matters far beyond 045
---

Approved on all three, and your DefTerm analysis is the most valuable thing anyone has produced
this hour. Answers in order, then a spawn budget.

## 1. `DETACHED_PROCESS`: YES, make the swap

Your reasoning is right and the evidence supports it: stdin/stdout/stderr are already redirected
to file handles, so the child never needs an interactive console; `CREATE_NEW_CONSOLE` creates one
anyway; and a console created on Win11 with both `DelegationConsole`/`DelegationTerminal` at the
all-zero GUID goes through the DefTerm hand-off to Windows Terminal — which is a GUI app living on
the user''s own interactive desktop. `STARTUPINFO.lpDesktop` governs where the CHILD lives, and
there is no reason to assume Terminal''s hand-off honours it for the window IT then draws.

**And you are right about the scope.** If that is the mechanism, then every ordinary
`run-offscreen.ps1` run flashes a console on the user''s screen once — your loop only turned one
flash into a strobe. That undercuts task 043''s headline claim, which I passed on to the user as
"tests no longer touch your screen". I have to correct that with them, and I would rather correct
it with your fix already in hand.

`DETACHED_PROCESS` (0x00000008) removes the class rather than fighting a registry setting. Make it
the change, keep the existing comment''s intent but rewrite it to say why a detached child is
correct HERE (redirected handles, no interactive console wanted, DefTerm hand-off avoided).

## 2. The header-branch proof: take option (a)

The exit-code overflow is the operative defect, you proved it live with a single spawn
(`-2146232797`, the exact value 039 hit, old code throwing `OverflowException` on it), and that is
enough. Do NOT keep chasing the header branch with spawn loops — you already showed 20 attempts
cannot reliably hit timing that a script driving a subprocess controls. Say in the PR that the
header branch is guarded but not reproduced, and why. An honest "guarded, not reproduced" beats a
hundred more spawns.

## 3. Spawn budget, explicit

You may spawn up to **8 processes total** for the rest of part 0, and every one of them must be
`DETACHED_PROCESS` after your fix. No loops. If you need more than 8, message me first with what
and why — I will almost certainly say yes, I just want it visible before it happens rather than
after.

Suggested use of them: two to prove `DETACHED_PROCESS` produces no console at all (one before,
one after, so you can say the difference is measured rather than asserted), one to re-prove the
exit-code path still works detached, and the rest in reserve.

**How to prove "no console appeared" without asking the user:** count `conhost.exe` and
`WindowsTerminal.exe` processes immediately before and after the spawn, and check the child''s own
`GetConsoleWindow()` is NULL. A process that has no console cannot have one drawn for it, on any
desktop, by any hand-off protocol. That is a positive check rather than "nobody complained".

## 4. Your discipline note

Accepted, and the ten-spawn line is the right instinct. One correction to how you framed it: the
loop was not wrong because it was 50 iterations — it was wrong because nobody could see it was
running and it had no bound in wall-clock time. A visible, announced, bounded 50 would have been
fine. Announce, bound, and it is yours to judge.

## 5. Part 0 shipping

Both named fixes plus the `DETACHED_PROCESS` change go in the same part-0 PR — they are one
finding wearing three hats. `run-ci-local.ps1` at the head, note the Actions billing outage, and
tell me the receipt filename. I will merge it ahead of everything else in the queue.
