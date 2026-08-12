---
from: conductor
to: user
sent: 2026-08-12T22:42:46Z
subject: Architecture review done -- top finding is our merge gate itself, confirmed by measurement. Nothing bad got through tonight, also measured
---

The review is done: `work/reports/052-architecture-review.md`, nine issues (#65–#73), no code touched.

**Its top finding is the merge gate I have been using all night**, so I verified that one myself before relaying anything else.

## 1. The gate could attest a pass for a run that failed — confirmed, measured

`run-ci-local.ps1` calls `Invoke-Pester -Path tests -CI -PassThru`. Pester's `-CI` switch **exits the process** on a red run. Line 128 (`throw`) and line 251 (write the receipt) never execute. So a red run leaves whatever receipt was there before — and if that was a PASS at the same sha, `merge-task.ps1` accepts it. With GitHub Actions dead on billing, that receipt is the *entire* gate.

I did not take that on the report's word. I built a deliberately-failing Pester suite in a scratch directory and ran it the same way:

    Invoke-Pester -Path tests -CI -PassThru
    Write-Host "REACHED-AFTER-PESTER ..."     <- never printed
    child exit code: 1

The line after Pester never ran. **Confirmed.** ([#72](https://github.com/inwenis/decompile-sc/issues/72))

## 2. But nothing bad got through tonight — also measured

The obvious next question is whether the three PRs I merged tonight (#55, #61, #64) rode in on a stale receipt. So I ran the full local CI against current `main`, which contains all three:

    ci-local: PASS  main@486b9b2
    Pester 77/77, hooktest 0 failures, game-content-guard 1156 files, python OK

Green. The defect is real and the gate needs fixing before the next merge; it did not let anything through tonight.

## 3. Your three questions, answered

**Clean?** *"Cleaner than its history suggests, and unevenly."* The address discipline is genuinely excellent — every engine address carries evidence, zero hardcoded addresses in shipping C++ outside two tables. The newest code embodies every hard-won rule; the older code predates those rules and was never brought forward. That **gradient**, not sloppiness, is the real problem.

**Duplication?** Yes — and the expensive kind is duplicated *mental models*, not code. `sc_hudrow.cpp` still carries the paint-order model task 039 disproved, which is exactly why your page indicator is invisible. Meanwhile 25 copies of `Assert-That` are broad but harmless. The dangerous copies are the ones that **drifted**: three different parsers for the same log line, one of which silently drops the only field that says anything was drawn.

**Invariants?** Per-frame ones, mostly yes, and visibly better after each burn. But the cross-game invariant — *"this record belongs to this game session"* — **exists nowhere**. Tonight's save/load bug is one instance; the review found **six more of the same class**, including a byte-identical copy of the same flawed liveness check in the upgrades module. One session epoch would close all seven ([#67](https://github.com/inwenis/decompile-sc/issues/67)).

## 4. The answer to "why does this keep happening"

This is the part I did not expect and think is the most valuable thing in the report. The repeated "checks that cannot fail" are **structural, not bad luck**:

1. every oracle is a `printf` on one side and a regex on the other, with no contract between them — hence three parsers that drifted apart;
2. there is no shared verdict machinery, so each suite is frozen at whatever rule maturity existed on its birth date (only 2 of 18 suites can even report INCONCLUSIVE);
3. **a falsifiable oracle costs a task; a vacuous one costs a line.** Nothing in the architecture makes the honest check the cheap one;
4. an A==B round-trip defaults to vacuous unless someone plants a witness — which is precisely what 051 had to invent from scratch tonight.

## 5. Also found

Five plugin counters printed and asserted `== 0` that are **never incremented anywhere** — the money-conservation assertions cannot fail ([#66](https://github.com/inwenis/decompile-sc/issues/66)). A conformance suite that can print "6 of 6 episodes" and PASS with every episode skipped ([#68](https://github.com/inwenis/decompile-sc/issues/68)). A literal `x -eq x` tautology ([#69](https://github.com/inwenis/decompile-sc/issues/69)). And no build identity anywhere: a green run cannot name the DLL or commit it tested ([#73](https://github.com/inwenis/decompile-sc/issues/73)) — the structural form of the "merged is not deployed" confusion you and I hit at 21:00 tonight.

It also stated its own coverage limits honestly: `sc_fanout.cpp` got a full read, the Python fixture generators and the probes are a second pass.

## 6. My recommendation for what happens next

Fix [#72](https://github.com/inwenis/decompile-sc/issues/72) first and before any further merge — it is small, and it is the thing standing between us and a bad merge while Actions is down. Then [#67](https://github.com/inwenis/decompile-sc/issues/67), the session epoch, because it closes seven bugs including the one that affects your actual play.
