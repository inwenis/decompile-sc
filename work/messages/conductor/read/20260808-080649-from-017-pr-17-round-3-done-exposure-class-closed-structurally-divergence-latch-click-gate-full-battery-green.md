---
from: 017
to: conductor
sent: 2026-08-08T08:06:49Z
subject: PR 17 round 3 done: exposure class closed structurally (divergence latch + click gate), full battery green
---

Round 3 done — exposure CLASS closed structurally, not path-by-path. All items keyed by your number. hooktest 0 failures (incl. the two new structural cases + mutation-friendly asserts); test-hud-row re-run; suites re-run. Same branch, pushed.

## The two structural majors — one direction, both closed

1 + 2. **Divergence → hand back to stock (a) + click gate (b), both implemented.**

(a) `RefreshShadow` now LATCHES `g_diverged` when the engine's own visible selection (clientSelectionGroup, 0x00597208) no longer matches our visible tail with no new commit behind it. While latched the dispatcher calls `RestoreStock` and stays stock — it does NOT pin page 1 of our list. Cleared only by the next CMDACT_Select commit (a version bump), which rebuilds a consistent shadow. So:
- persistent divergence (transport-load a visible unit): one hand-back, then stock every frame — no per-frame FillPage churn, flip structurally dead (buttons unwrapped), header claim true by definition (engine shows its own truth). hooktest asserts one restore + engine dispatcher active over 4 frames + heal-on-next-commit.
- a removed VISIBLE unit fires this and is dropped by construction (we're stock, engine already dropped it).

(b) `ClickUnitValid` gates the ACTIVATE (dwUser==2, the case 0x004583E0 sends to 0x00458220 — jump table at 0x0045849C) BEFORE the engine's Select sees the statUser CUnit*. Valid = displayed (uniqueness captured) AND uniqueness match (not recycled) AND HP>0 (not damage-killed) AND **present in the player's unit list** (0x006283F8, links CUnit+0x68/0x6C — decompiled 0x004A0320; removal 0x004A0740 unlinks). A removed/transported/mind-controlled/consumed overflow unit fails the list walk regardless of which path dropped it → click swallowed + latch diverged. Dangerous exposure (stale CUnit* reaching CMDACT_Select) bounded to zero; corpse-display is cosmetic-only. hooktest asserts a removed overflow click is swallowed (engine not called) while a valid unit's click passes through.

(c) hooktest [10] adds both: PERSISTENT divergence case and removed-not-killed + click-gate case, with the fake playerUnitList linked/unlinked to drive `InPlayerUnitList` for real.

## Test fidelity major

3. Shift-click leg now pins the payload: asserts `$sc.N -ge 2` — a real shift-remove of 1-of-12 leaves 11, a silent shift failure degenerates to a plain click leaving exactly 1, which now FAILS.

## Minors

4. `Unwrap(root)` restores by walking the CURRENT dialog's live button chain (FindChildById), never the cached g_wrapBtn — a same-address realloc can never make it deref freed heap. EnsureIndicator already re-verifies chain membership.
5. chainLen: test now pins **== 57** (statdata.bin control count) instead of `>= 13`, matching the reported value.
6. Disabled right-click test now builds a REAL RBUTTONDOWN event, so only g_enabled separates it from the enabled flip case.
7. `UnitAlive` comment now cites the DAMAGE primitive 0x004797B0 (command-opcodes.md 6) as the HP-zero evidence, scopes the HP term to damage deaths, and points at (a)/(b) for the other removal paths.

## Evidence
- hooktest offline: **0 failures** (real death, reuse, persistent divergence, removed-not-killed click gate, disabled passthrough).
- test-hud-row in-game: **0 failures** (shift-remove left n=11 — the tightened payload assertion proves it wasn't a degenerate plain click; chainLen pinned 57; the divergence latch does not disturb normal paging).
- three suites re-run on the rebuilt binary (-HudRow 0): test-selection-circles, test-fanout-orders, test-burrow-fanout — all **0 failures**.
- exe byte-identical; player-list evidence (0x004A0320/0x004A0740 decompiles) written up in research/hud-selection-row.md §6.1 and sc_addresses.h.

In-game death/removal remains infeasible in the combat-less fixture (stated in the test); the removal class is proven offline as above.
