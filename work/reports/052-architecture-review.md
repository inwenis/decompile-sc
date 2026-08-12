# Task 052 — The first architectural review: duplication, invariants, and checks that cannot fail

Reviewed at `486b9b2` (2026-08-12). Scope: the plugin (`tools/plugin/src`, ~17k lines C++) and the testing framework (`tools/plugin/*.ps1` ~23k lines, `scripts/`, `tests/`). Read-only; no product code touched. Method and coverage limits: §7.

## 1. The four questions, answered plainly

1. **Have we ever done an architectural review?** No. This is the first. 51 tasks in six days; the one prior audit (022) was a domain audit of ability semantics, not a pass over the system.
2. **Is the code clean?** Cleaner than its history suggests, and unevenly. The address discipline is genuinely excellent (every engine address carries evidence; zero hardcoded addresses in shipping C++ outside the two tables). The newest code embodies every hard-won rule; the older code predates the rules and was never brought forward. That gradient — not sloppiness — is the repo's real cleanliness problem.
3. **Do we have duplication?** Yes, and the expensive kind is duplicated *mental models*, not code: `sc_hudrow.cpp` still carries the paint-order model that task 039 disproved in `sc_queueind.cpp`, and its indicator is invisible because of it (§3, F1). Code duplication is broad but mostly benign (25 copies of `Assert-That`); the dangerous copies are the ones that drifted (three different parsers for the same `HUDROW show` line, one of which silently drops the only drawn-ness field).
4. **Do we handle invariants correctly?** The per-frame invariants, mostly yes — and visibly better after each burn (liveness gates, thread-ownership snapshots, bounded walks). The cross-game invariant — "this record belongs to this game session" — **exists nowhere**. Issue #63 is one instance; the review found six more of the same class (§3, F3). And the repo's dominant defect class is confirmed structural, not bad luck: checks that cannot fail keep appearing because nothing in the architecture makes a falsifiable check cheaper than a vacuous one (§4).

The evidence says the user's instinct was right on all three concerns, and the highest-value finding is the one they didn't ask about: **the merge gate itself (the local CI receipt) can currently attest a pass for a run that failed** (§3, F4).

## 2. What is actually good

Stated first because §3 is long, and because these are the parts to *copy*, not just keep:

1. `sc_addresses.h` — 168 evidence-carrying address defines; a sweep found not one evidence-free entry, and not one hardcoded engine address in shipping `.cpp` code outside the tables.
2. `sc_queueind.cpp` — the post-039 reference implementation: tail-splice with the corrected paint model documented (`:310-325`), baseline-diff oracle with honest `-1` for "no answer" (`:734-764`), positive controls (`refInk`, `surfInk`), game-thread snapshots for observer reads (`:62-71`).
3. `test-save-load.ps1` — the best-hardened suite: a load *witness* (a mutation the save cannot contain, asserted positive first, `:793-831`), measurement-window gating (`:287-310`), per-arm seam coverage lines (`:353-359`), `INCOMPLETE` distinct from `PASS` (`:969-973`).
4. `drive-game.ps1`'s browser model, fixture ownership, `Set-ScMarker`, and the marker→oracle handshake (`Get-ScUnitState`/`Get-ScWorldState` waiting for completion sentinels).
5. `hooktest.cpp` — run-order part numbering (issue #35's fix), per-PID logs (#36's fix), unbuffered output so a crash names its part, exit code from the failure count.
6. `tests/make-test-map.Tests.ps1` and `tests/drive-game.Tests.ps1` — the two Pester files whose expectations come from *outside* the code under test.

## 3. Ranked findings — Tier A: can make us believe something false today

Each has a GitHub issue (or extends an existing one). Ordered by blast radius.

### F1 — The HUD-row page indicator: a cannot-fail oracle guarding a feature broken by a duplicated wrong model — issue #65

- `test-hud-row.ps1:332-333` asserts "and the engine DREW it: ink > 0". `indInk` is a raw non-background byte count (`sc_hudrow.cpp:600` → `ScQueueIndSurfaceInk`) over a 148×16 box (`sc_hudrow.cpp:516-528`) sitting on saturated wireframe art → reads 2368 for every string, drawn or not (measured, task 048).
- The same file's module splices its indicator at the **head** of the child chain under the comment "drawing last in our act keeps its text on top" (`sc_hudrow.cpp:487-492`, code at `:536-537`) — the exact model `sc_queueind.cpp:310-325` disproved in task 039 (the redraw walk paints head→tail; earlier = under).
- `hooktest.cpp:4152-4160` asserts tail-position Z-order for QIND and says in its own comment "this is the assertion sc_hudrow's suite was missing".
- **Cost if left:** the flagship UI feature reads verified-drawn in a green suite while being invisible — it already did, twice (tasks 033, 048). Task 048 (in flight) owns the module fix; #65 tracks the suite oracle so a regression net exists afterwards.

### F2 — Five plugin counters are asserted zero and cannot ever be non-zero — issue #66

- `SC_PRODQ_STAT_MINERALS_SPENT`/`GAS_SPENT`/`REFUSED_COST` and `SC_UPGQ_STAT_MINERALS_SPENT`/`GAS_SPENT` are declared, printed (`sc_prodqueue.cpp:526,539-541`; `sc_upgrades.cpp:561`) and **never incremented anywhere**.
- Asserted `-eq 0` in 8 hooktest Checks ("the plugin spent NOTHING") and three game suites (`test-production-queue.ps1:1511`, `test-group-queue-over-five.ps1:601-602,767-770`, `test-upgrade-queue.ps1:679-680`).
- **Cost if left:** the money-conservation claim — the one the whole refund design rests on — is carried by assertions that can only fail if a future author who breaks the rule also politely instruments their breakage. Task 030's class, living in the plugin itself.

### F3 — No game-session epoch: issue #63 is one of seven — issue #67

- `sc_upgrades.cpp:93-100` is byte-identical to prodqueue's `RecordStillLive` → stale records start **paid research in a loaded game** (#63's unfiled sibling).
- `sc_fanout.cpp:689` `g_plan`: a budget-deferred plan drains "on the next command" (`:826-830`) with raw order bytes and old unit records — nothing bounds that to the same game.
- `g_shadow`/`g_accum` (`sc_fanout.cpp:201,206`) live until the next commit; `g_shadowVersion` (`:211`) cannot express "different game", and `sc_hudrow.cpp:328` trusts it.
- `g_group` (`sc_fanout.cpp:950`): save/load within a session restores the same pointers, so the containment defence passes and a pre-save group is re-injected.
- `sc_circles.cpp:37` `g_circled` holds `CSprite*` heap addresses across game end.
- **Cost if left:** more #63-shaped user reports (free units, phantom research, replayed orders), each costing a task to diagnose. One mechanism (a `g_session` counter bumped from the engine's game-start clear `0x004EEC30`, already known at `sc_fanout.cpp:989`) closes all of them.

### F4 — The local CI receipt can attest a pass for a run that failed — issue #72

- `run-ci-local.ps1:127` uses `Invoke-Pester -CI`, which **exits the process** on failure — before the receipt write at `:233-251`. The receipt path is deterministic per sha, so an earlier green run's `pass` receipt survives a later red run verbatim, and `merge-task.ps1 -LocalCiReceipt` accepts it.
- The receipt sha comes from `HEAD` with no dirty-tree check (`:48-49`); the validator matches by `StartsWith` with no minimum length (`lib/ci-local.ps1:71`).
- Sub-step skips are invisible: `:129` records `PassedCount` only, so all ~19 `make-test-map` cases skipping on a python-less machine reads as pass. The skip-classification mechanism itself (`:59-80`) has zero test coverage.
- **Cost if left:** with Actions dead, this receipt is the *entire* merge gate. This is the highest-trust seam in the repo attesting more than it checks.

### F5 — No build identity: a green run cannot name the code it ran — issue #73

- `build.ps1` stamps nothing; `run-with-plugin.ps1:372-377` picks the DLL by `Test-Path` alone with `-Build` opt-in → edit `src/`, forget `-Build`, and every suite silently tests the previous DLL; the ATTACH banner (`scplugin.cpp:753-770`) carries no build id; `deploy.ps1:521-524` checks plugin file freshness, not source identity.
- **Cost if left:** the 2026-08-11 "merged is not deployed" incident, structurally guaranteed to recur — in-game verdicts unattributable to commits, in both directions (false green for new code, false regressions against stale DLLs).

### F6 — test-random-conformance: the regression gate can go green having done nothing — issue #68

- `episodesRun++` at `:843` precedes all four skip paths (`:881,890,923,927`) → "episodes run: 6 of 6" + PASS printable with zero bursts pressed. The task-041 `INCOMPLETE` protection is present but this route bypasses it without an exception.
- The seam counter (`:933`) counts planned intent, never confirmed reach; `groupOverflowEpisodes=0` warns loudly (`:1026-1028`) but does not gate the verdict or exit code.
- `-Profile upgrades`/`hudrow` exist in the plan generator (`random-conformance-plan.ps1:244-252`) but the runner dispatches only `indicator`/default (`:936-939`) → a green "upgrades" run presses Train buttons and tests none of sc_upgrades.
- **Cost if left:** this is the suite the repo calls its conformance gate; task 041's incident (a) can recur in a new costume.

### F7 — Vacuous arms in three suites — issue #70 (issue #45's class)

- `test-combat-death.ps1:977,982`: the "no dead tag reached the wire" pair is disjoint-by-construction — a dropped unit never reaches the tag list, a wrongly-passed one never produces a verdict line, so the sets cannot intersect *whatever the gate does*. `:1098` repeats issue #45's shape (row-missing not intersected with `$deadTags`).
- `test-sunken-acquire.ps1:329,334`: the whole plugin-vs-stock comparison is silently skippable, and its equality passes when both arms no-opped; `:284` samples the acquire order once where HP correctly uses min-over-samples.
- `test-building-parity.ps1:614` (MIXED refusal = no-op equality with no click-landed evidence) and `:734-736` (rally asserted as one bucket, without the "it MOVED" comparison its own comment promises — `test-building-groups.ps1:613` has the correct guard).
- **Cost if left:** three suites' headline claims are partially decorative; a regression in any of them stays green.

### F8 — test-upgrade-queue: a literal tautology on the money claim — issue #69

- `:553-554` asserts `$mineralsAfterFirst -eq $mineralsAfterFirst`. The pay-once-per-start claim in that arm is unasserted. The first-cancel arm (`:577-592`) is asserted entirely from plugin bookkeeping with no wire evidence (the second arm at `:603-605` shows the correct pattern).
- **Cost if left:** the suite that owns upgrade-queue money semantics can't see them break.

### F9 — Issue #37 regression: six raw `Set-Content` marker writes — issue #71

- `test-production-queue.ps1:400,545`, `test-upgrade-queue.ps1:167`, `test-group-production.ps1:157`, `probe-upgrade-queue-indicator.ps1:123`, `test-widescreen.ps1:140` (that one adds a trailing newline too) bypass `Set-ScMarker` — the helper that exists because `Set-Content`'s share mode throws with *certainty* on overlap with the plugin's reader.
- **Cost if left:** intermittent mid-run throws in the highest-polling suites; already paid for once (task 031).

### Extension of issue #60 (comment posted, no new issue)

9 of 18 suites never take the chain-level launch lock at all; `run-offscreen.ps1`'s timeout kill skips suite teardown while the OS frees the lock with the game alive; `Exit-ScLaunchLock` never clears the lock file's content, so timeout messages name dead pids (three conductor incidents cited in the comment).

## 4. The structural answer: why "checks that cannot fail" keeps happening

The task asked whether five instances means five unlucky authors. It does not. Four architectural facts manufacture this class:

1. **The oracle seam is printf → regex, with no contract.** The plugin prints lines; suites parse them with private, mostly positional regexes. Three drifted copies of the `HUDROW show` parser exist (`test-hud-row.ps1:89` full; `test-combat-death.ps1:451` and `test-control-groups.ps1:395` truncated — combat-death's predates task 033 and silently drops `indInk`, the only drawn-ness field). `sc_prodfan.cpp:230`'s `INVALID` line variant fails `test-random-conformance.ps1:403-422`'s row regex and the building silently vanishes from the result set — an absence-assertion hazard baked into a parser. A format string can change in one place and turn N assertions into 0 without a single failure.
2. **There is no shared verdict machinery, so every suite is frozen at the rule-maturity of its birth date.** `Assert-That` is defined 25 times; the task-041 `INCOMPLETE` rule exists in 2 of 18 suites; seam-coverage printing in ~3; the load-witness idiom in 1. The rules live in AGENTS.md prose and retrofit is manual — which is why tonight's suite (save-load) is excellent and last week's are the findings list. The framework (`drive-game.ps1`) supplies oracles and input primitives but no assertion, coverage, or completion accounting.
3. **The falsifiable oracle is expensive and the vacuous one is one line.** A raw count (`ink > 0`, `-eq 6`, `count -le 5`) is a single expression; the honest version (baseline-diff with capture-lifecycle rules, witness mutations, positive controls) took task 039 a full task to build — and it lives as private statics in `sc_queueind.cpp`, unusable by `sc_hudrow` twenty lines away. Nothing structural makes the right thing the easy thing.
4. **Round-trip comparisons default to vacuous.** Any `A == B` assertion passes when the operation no-opped; only a witness (a change the operation must undo, proved positive first) makes it falsifiable. test-save-load learned this at cost (`:793-831`); no shared helper carries the idiom, so the next round-trip suite starts from zero again.

Corollary worth naming: the plugin's own log lines split into two trust classes — engine read-backs (WORLD, STATQ engine slots, SELSNAP) and **self-echoes** (`FANOUT select` tags, `HUDROW indicator=`, `GROUP ... now holds`, `CIRCLES show n/n`), where the module prints its own buffer. Several suites' headline verdicts rest on the second class (`test-control-groups.ps1:296` — the task's whole point — asserts `g->count`, the plugin's own store). Nothing in the line format marks which class a field belongs to.

## 5. Duplication — models first, then code

1. **Contradicting models (the expensive kind), all cited in §3-F1:** paint order (hudrow vs queueind), drawn-ness oracle (raw ink vs baseline diff). One more: **bounded vs unbounded dialog walks** — `sc_queueind.cpp:176-185` bounds every child walk because a torn `next` on the observer thread must end a walk, not spin it; `sc_hudrow.cpp:255-260,483,555,591` are all unbounded, and `:591` runs on the observer thread against a game-thread-owned list. A torn pointer there hangs the process instead of failing a read.
2. **Drifted code copies (silently different behavior):**
   - `HUDROW show` parsers ×3 (§4.1).
   - `Get-QInd`/`ConvertFrom-QIndLine` ×3 with dropped fields and mixed marker-write discipline (`probe-upgrade-queue-indicator.ps1:88-90` admits "copied rather than shared").
   - Suite preamble: the launch-lock and pristine-SHA-ordering steps differ per copy lineage (`test-combat-death.ps1` hashes the exe *after* building fixtures at `:602-608`; everyone else gates first).
   - `Select-ScUnitsByMap` ×4 (`test-building-groups.ps1:212` original; copies in group-production `:254`, building-parity `:262`, group-queue-over-five `:321`) — the drag-box-by-memory primitive, absent from drive-game.ps1.
3. **Benign-but-broad:** `Assert-That` ×25, `Step` ×23, `Shot` ×20, `Get-World`-style wrappers ×11, the fanout policy list ×2, the menu walk ×~8. Consolidation is worth one mechanical task, not more (deferred, §8).

## 6. Invariants — what is assumed that nothing checks

1. **"A record belongs to this game session"** — nowhere expressed; seven state stores rely on it (§3-F3, issue #67).
2. **"The engine's own result is the oracle"** — enforced by convention only; §4's self-echo class is where it leaks. The strongest counter-example to copy: `test-control-groups.ps1:419-423` cross-checks tags between two modules reading two different sources.
3. **Thread ownership** — the rule ("frame state is snapshotted by the game thread") is followed where it was burned (`sc_queueind.cpp:62-71`) and violated quietly elsewhere: `ScFanoutLogState` (`sc_fanout.cpp:2511-2517`) reads shadow counters and `g_plan.active` with no lock from the observer heartbeat, three lines from a sibling that takes the lock; `ScFanoutLogStats` walks `g_group` from the detach thread (`scplugin.cpp:930`). Diagnostics-only today (task-030 rule: a wrong number in a log is worse than none), plus `sc_hudrow`'s exports are unsynchronised on a public header waiting for their first observer-thread caller.
4. **"The baseline belongs to this dialog instance"** — `sc_queueind.cpp:965-981` resets on `root != g_dialog` and its own comment names the honest reason; the same-address-realloc case (which `sc_hudrow.cpp:454-459` handles for its own pointers by re-deriving from the live chain) leaves `g_baseValid` standing. Narrow window, oracle-only impact.
5. **"The suite ran what it claims"** — the invariant test-save-load and test-random-conformance encode (episodes/witness/INCOMPLETE) and 16 suites do not: silently skippable arms in production-queue (`:1103-1104` fifth-icon arm, `:1390` a literal `Assert-That ... $true` as a skip marker), widescreen (PASS reachable with zero pixel oracles when the control walk fails, `test-widescreen.ps1:465,528`; no completeness flag at all), sunken/ability (§3-F7), upgrade-queue `-NoDrain` (claims 3-5 skipped, exit 0).

## 7. Coverage — what this review read, and what it did not

- **Read end-to-end by the reviewer:** AGENTS.md; `drive-game.ps1`; `sc_hudrow.cpp`; `sc_queueind.cpp`; `sc_prodqueue.cpp`; `scplugin.cpp`; `test-save-load.ps1`; `sc-launch-lock.ps1`; `hooktest.cpp` head/harness/main; targeted regions of `sc_fanout.cpp` (plan/drain/emit), `sc_upgrades.cpp` (record/liveness), `test-hud-row.ps1`, `test-building-parity.ps1`, `test-combat-death.ps1`, `test-random-conformance.ps1`, `random-conformance-plan.ps1`, `run-ci-local.ps1`, `lib/ci-local.ps1`.
- **Swept by eight parallel review agents, with every Tier-A claim re-verified line-by-line in the main review before ranking:** all 18 test suites, the conformance plan/episodes pair, the C++ static-state and address census, `scripts/` + `tests/`, the duplication cross-cut.
- **Not read, in honesty:** `sc_fanout.cpp` in full (2,297 lines — the largest and most-shared module; only its state, plan, and emit paths were examined); `sc_card.cpp`, `sc_circles.cpp`, `sc_screen.cpp`, `sc_prodfan.cpp` beyond their census entries; most `probe-*.ps1`; the Python tooling (`make_test_map.py`, the Ghidra/renderer sweeps); `tools/deploy.ps1` beyond the hash sites; `run.ps1`/console UI.
- **A second pass should start with:** (1) `sc_fanout.cpp` in full — it owns the most cross-module state and the widest hook surface; (2) `make_test_map.py` and friends — a fixture-generator bug is a wrong-conclusion machine and it has already produced one (task 026's PTEx index bug); (3) the probes, which feed research/ conclusions but sit outside every gate.

## 8. DEFERRED — real, but merely untidy (no issues opened; none can change a conclusion)

1. Consolidation: `Assert-That`/`Step`/`Shot`/`Get-World` ×25/23/20/11 → one dot-sourced `sc-suite-common.ps1`; promote `Select-ScUnitsByMap`, `Assert-Every` (`test-stim-fanout.ps1:140`, the empty-set-refusing assert), `Get-MinDistance`, and the incremental log tail (`test-random-conformance.ps1:297-326`) into drive-game.ps1.
2. Performance: whole-log `Get-Content` re-reads in every oracle poll (documented as "the reason a long run hangs" at `test-random-conformance.ps1:287-292`); the faster tail exists in one suite.
3. Redundant assertions that restate arithmetic or repeat a sibling (`test-control-groups.ps1:369-370,482-483`; `test-group-queue-over-five.ps1:599-600`; `test-stim-fanout.ps1:271`; `test-building-groups.ps1:508-509`) — harmless, but they pad "N checks passed" counts with checks that cannot fail independently, which flatters coverage.
4. `test-widescreen.ps1:276` `if ($true)` dead conditional; `-CaptureFrames` doesn't do what its help says.
5. `sc_screen_patches.h` is a second address table outside `sc_addresses.h` — documented and evidenced, but the "addresses live in sc_addresses.h" rule has an unstated exception.
6. `sc_addresses.h:1231-1232` (`SCROLL_STEP_X/Y`) — the only two defines relying solely on a block-level citation.
7. Naming drift: `Remove-MyFixture` vs `Remove-MyFixtures`; `Set-ScGameType` called with and without `-LogPath` in different suites.
8. `tests/deploy-runtime.Tests.ps1` asserts on source *text* with a `> 2` threshold against 5 actual dot-sources; `tests/game-type.Tests.ps1:133-135` restates the implementation's constant.
9. try/finally-without-catch in `test-group-queue-over-five.ps1:731` and `test-group-production.ps1:334` — a throw skips the final accounting block entirely (no false PASS; no verdict at all). Fold into any touch of those suites.
10. Exit-code hygiene: four group suites launch `run-with-plugin.ps1` through a pipeline that discards its exit code (PID-regex is the only gate); `| Tee-Object` still swallows suite exit codes at the documented call sites (known from task 041; unchanged).

## 9. Issue ledger

| # | Title (short) | Finding |
| --- | --- | --- |
| #65 | hud-row blind ink oracle + pre-039 paint model | F1 |
| #66 | dead stat counters asserted zero | F2 |
| #67 | no game-session epoch (class of #63) | F3 |
| #72 | CI receipt can attest a failed run | F4 |
| #73 | no build identity for the running DLL | F5 |
| #68 | conformance gate: skip-blind episodes, phantom profiles | F6 |
| #70 | vacuous arms in combat/sunken/parity (#45 class) | F7 |
| #69 | upgrade-queue tautology + unwitnessed cancel | F8 |
| #71 | marker-write regression (#37 class) | F9 |
| #60 (comment) | launch-lock chain inventory | §3 ext |

Pre-existing issues this report leans on rather than re-files: #45 (fanout Patrol green-by-accident), #63 (over-cap items survive a load), #44 (>12 building group never exercised), #58 (fifth-slot rendering never captured).
