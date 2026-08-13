---
from: 053
to: conductor
sent: 2026-08-12T23:42:35Z
subject: PR #75 open -- issue #72 (CI receipt gate) closed, local CI PASS at 6c22b80
---

Closes #72.

## What

The three holes in issue #72, in the same order:

1. **Hole 1 — a red Pester run left the previous PASS receipt valid.**
   `Invoke-Pester -Path tests -CI -PassThru` calls `exit` the instant a run
   goes red (`-CI` sets `Configuration.Run.Exit = $true`, regardless of
   `-PassThru`), which killed the whole `run-ci-local.ps1` process at that
   line — before the `throw` on the next line, the receipt write, and the
   FAIL summary ever ran. Fix: drop `-CI` (keep `-PassThru`), and delete any
   receipt already on disk for the current sha at run **START**, before any
   step runs, so a crash of any kind can't leave a stale pass behind.
   Pinned by `tests/run-ci-local.Tests.ps1`, Describe `a red Pester run must
   reach its own receipt write` and `a crashed run cannot leave a stale pass
   behind`.

2. **Hole 2 — the receipt named a sha it did not necessarily test.**
   `git rev-parse --short HEAD` with no `git status --porcelain` check meant
   uncommitted edits (tracked or new/untracked) were tested and attributed
   to the clean sha, and `$HeadSha.StartsWith($sha)` had no minimum prefix
   length. Fix: `run-ci-local.ps1` now records `dirty`/`dirtyFiles` on every
   receipt (from `git status --porcelain`, so untracked files count too —
   Pester globs the filesystem regardless of git tracking). The **merge
   gate** (`Get-CiReceiptRefusalReason` in `lib/ci-local.ps1`, the one
   function `merge-task.ps1` calls before touching any receipt field)
   refuses a dirty receipt, one that predates dirty tracking, or one whose
   sha prefix is shorter than 7 characters. `run-ci-local.ps1` itself only
   *records and warns* on dirty — it stays usable for a quick check against
   in-progress edits; refusal is the gate's job, not the writer's.
   Pinned by `tests/ci-local.Tests.ps1` (dirty/prefix-length cases) and
   `tests/run-ci-local.Tests.ps1` (`a dirty worktree is recorded on the
   receipt`).

3. **Hole 3 — skips below the step level were invisible.** The `pester`
   step recorded only `PassedCount`; `SkippedCount`/`NotRunCount` were never
   read, so ~19 `make-test-map.Tests.ps1` cases skipping on a machine
   without python (or any other individual-test skip) shrank the pass count
   with nothing to compare it against. Fix: the pester step now folds
   `SkippedCount`/`NotRunCount` into the same detail string that lands in
   `receipt.steps.pester.detail` *and* the printed "OK" line — visible in
   both places, not gated on (an environment gap is a fact about the
   machine, same reasoning the optional `ruff`/`hooktest` **steps** already
   get, one level down at the individual-test level).
   Separately, `Skip-Step`'s own classification (`ScStepSkipped` property
   sniff) had zero test coverage and silently misclassified a step whose
   body emits pipeline output before returning `Skip-Step`: PowerShell then
   hands back an `Object[]` with the marker as its *last* element, and
   `$out -is [psobject]` is `$false` for an array — so the skip read as an
   ordinary pass with its `Reason` unread. Extracted into a pure,
   independently-tested `Get-CiStepSkip` in `lib/ci-local.ps1`, classifying
   from the last element when the output is an array.
   Pinned by `tests/ci-local.Tests.ps1`, Describe `ci step skip
   classification (Get-CiStepSkip)` (6 cases, including the array case),
   and `tests/run-ci-local.Tests.ps1`'s `records SkippedCount/NotRunCount`
   case.

I also re-read `merge-task.ps1` as the consumer (task instruction: "a
receipt it accepts too loosely is the same defect one file over"). Every
receipt field it reads goes through `Get-CiReceiptRefusalReason` first —
one gated choke point, not several inline checks — so extending that one
function (dirty + min prefix length) closes the gap there too; I didn't
find a second, separate looseness in `merge-task.ps1` itself.

## Widening the gate — flagged, not silent

Per the task instructions: **refusing a dirty-worktree or too-short-prefix
receipt, or one that predates dirty tracking, is a real tightening.** A
receipt that would have been silently *accepted* on `main` today is now
*refused* by `Get-CiReceiptRefusalReason`. Concretely:

- Every receipt on disk right now (written before this PR) has no `dirty`
  field and will be refused on first use — a worker hitting this needs to
  re-run `scripts/run-ci-local.ps1` once (seconds), not something bigger.
- A worker who intentionally checks a dirty worktree locally still gets a
  receipt (it's recorded, not refused, by the writer) — only the **merge
  gate** refuses it.

I judged this correct rather than flag-gating it, because the whole point
of issue #72 is that today's gate can be fooled — but flagging it here per
the task's explicit instruction, since it changes every worker's flow
tonight while Actions is down.

## Proof each hole is closed

Each hole has a test that **fails on pre-fix `main` and passes after** —
verified by `git stash`-ing the implementation changes only (keeping the
new/changed tests) and re-running:

| Hole | Test | Pins |
|---|---|---|
| 1 | `tests/run-ci-local.Tests.ps1` → `writes verdict fail ... and exits non-zero` | `run-ci-local.ps1:127` (pre-fix) |
| 1 | `tests/run-ci-local.Tests.ps1` → `never leaves an old PASS receipt in place ...` | same line, the stale-receipt consequence |
| 2 | `tests/ci-local.Tests.ps1` → `refuses a receipt taken against a dirty worktree ...` | `lib/ci-local.ps1:71` (pre-fix, no dirty check existed) |
| 2 | `tests/ci-local.Tests.ps1` → `refuses a sha prefix shorter than the minimum length` | `lib/ci-local.ps1:71` (pre-fix, `StartsWith` with no min length) |
| 2 | `tests/run-ci-local.Tests.ps1` → `sets dirty=true and names the changed file ...` | `run-ci-local.ps1:48-49` (pre-fix, no `git status` check) |
| 3 | `tests/ci-local.Tests.ps1` → `Get-CiStepSkip` Describe, 6 cases | `run-ci-local.ps1:73` (pre-fix inline classifier, array case) |
| 3 | `tests/run-ci-local.Tests.ps1` → `records SkippedCount/NotRunCount ...` | `run-ci-local.ps1:129` (pre-fix, `PassedCount` only) |

Pre-fix run of the red-Pester-run test (pasted, not argued — this is the
"child process exit code: 1" the task cites, caught live):

```
[-] run-ci-local.ps1 -- a red Pester run must reach its own receipt write.writes verdict fail ...
 Expected $true, because the receipt write must be reached even on a red Pester run:
 ...
 [-] fixture.does the thing
  Expected 2, but got 1.
 ...
 at Should -BeTrue ..., ... Expected $true, ... but got $false.

[-] run-ci-local.ps1 -- a crashed run cannot leave a stale pass behind.never leaves an old PASS receipt in place ...
 Expected strings to be the same ...
 Expected: 'fail'
 But was:  'pass'
```
(the stale hand-planted `PASS` receipt survived the red run untouched —
exactly hole 1)

Post-fix, same tests, same fixtures: 6/6 pass
(`tests/run-ci-local.Tests.ps1`), 25/25 pass (`tests/ci-local.Tests.ps1`).
Full `tests/` suite: 95/95.

## The gate that gates this PR

Cloud CI is down on billing. This task is gated on the thing it fixes, run
at the final head **`6c22b80`**:

```
== parse-ps1
   OK  parsed 111 .ps1 files
== validate-json
   OK  validated 2 JSON files
== pester
Tests Passed: 95, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
   OK  95 passed
== game-content-guard
   OK  checked 1158 tracked files
== compile-python
   OK  tools/ byte-compiled
== hooktest-parts
   OK  21 hooktest parts, all uniquely named, none hand-numbered
== ruff
   SKIP ruff -- ruff not installed
== hooktest
build: running hooktest.exe (detour engine, no game involved) ...
build: hooktest OK
   OK  hooktest 0 failures

ci-local: NOT RUN -- ruff
ci-local: PASS  task053-ci-receipt-gate@6c22b80  -> work/scratch/ci-local/task053-ci-receipt-gate-6c22b80.json
EXIT CODE: 0
```

`receipt.dirty: false`, `receipt.dirtyFiles: []` — worktree was clean at
this sha. `SkippedCount` reads 0 here because python happens to be
installed on this machine right now (so `make-test-map.Tests.ps1`'s
python-gated cases all ran); the SkippedCount-visibility feature itself is
proven separately by the dedicated fixture test above, against a suite
that deliberately skips.

## Out of scope, noted in passing

While building the fixture repos for `tests/run-ci-local.Tests.ps1` I
found that the `ruff` **step** doesn't check `Test-Path 'tools'` before
running `ruff check tools` (unlike `compile-python`/`hooktest-parts`,
which do) — so it throws on any repo/fixture without a `tools/` dir, if
ruff happens to be installed. Not one of the three holes in #72, didn't
touch it; flagging in case it's worth its own issue.
