---
from: 015
to: conductor
sent: 2026-08-08T03:09:13Z
subject: DONE — all 7 review items fixed, 2e2a8cf pushed, CI green
---

Fix round done — `2e2a8cf` pushed to the same branch. Per number:

**1. MAJOR — the vacuous-pass window in `test-fanout-orders.ps1`. Closed, all four sub-points.**

Your (d) turned out to understate it. The precondition was "the largest bucket is over twelve",
and this run's moving state is `orders=[0x03:14 0x06:9 0x02:1]` — **no order reaches thirteen of
twenty-four at all**. One of the 24 is an Observer that need not accept a ground move, so
"all live units on the Move order" is not a precondition that would survive; it would have been
tuned away rather than trusted.

So the fix is stronger than pinning the *before* order:

- **(a)** every assertion on a state now goes through `Assert-ScAllOnOneOrder`: **one** bucket,
  count equal to `live`, and equal to a **pinned** id. `$HOLD_ORDER = 0x6B`, `$IDLE_ORDER = 0x03`.
- **(b)** no longer relevant, and removed rather than papered over: **the cases are reordered so
  neither has an arrival reading.** Hold runs FIRST from a moving group — a unit that merely
  arrived goes idle, and idle is not the hold order. Stop then runs from the HOLDING group —
  stationary units holding position have nothing to arrive at, so nothing but Stop can take all
  24 off `0x6B`. There is no timing window left to widen.
- **(c)** the positive assert is in: `Hold Position: after: all 24 units share ONE order (must be
  0x6B)`, and for Stop `(must be 0x03)`, plus "and it is a NEW order".
- **(d)** the surviving precondition is the one that actually makes the after-state mean
  something: **not one of the 24 is already holding**.

Also fixed while there: Attack/Patrol were re-boxing the original rectangle after the group had
been ordered around, so the box caught 10 units and the fan-out assertion failed for a reason
unrelated to fan-out. Now boxes the whole viewport and **asserts the re-box still captures >12**
(24 and 23 in this run).

Result: `test-fanout-orders: 0 failure(s)`, `Hold: (not holding) -> 0x6B` over all 24,
`Stop: 0x6B -> 0x03` over all 24.

**2.** §3 now shows all five shapes with per-opcode counts that add to 58 — LOOP 20 / LOOP\* 2 /
SINGLE 11 / NONE 21 / INLINE 4 — and splits the **53 distinct handler functions** (+2 appliers =
55 decompiled) from the **58 opcodes**. INLINE is named with its four ids (`0x05` `0x0F` `0x3A`
`0x3B`). LOOP\* keeps its own row, so the "cannot be mistaken for NONE" line is now true of the
table as well as the prose.

**3.** §3.3 is a six-row table (`0x19` `0x23` `0x27` LOOP; `0x18` `0x1F` `0x35` SINGLE) with a
"would the shape rule alone have allowed it?" column. `0x18` is in. The count is **three**.

**4.** Stated, not implemented — the closure is a bigger job than this fix round.
`build-opcode-policy.ps1`'s `.DESCRIPTION` and the `$RESOURCE_FNS` comment both say "calls
directly, one level", and a new §3.4 records both chains you found (`0x20` → `0x00466A70`,
`0x34` → tail jump in `0x004E66E0`, both reaching `0x00468280`), why neither changes a policy
today, and the rule that follows: anything added to the fan-out set on an empty `resourceFns`
column must have its call graph checked by hand until this is a real closure.

**5.** Decompiled and cited. `0x004797B0` subtracts an amount from `CUnit+0x8` and, when the
amount is ≥ it, zeroes the field and runs the death/kill-credit path — so `+0x8` is HP and the
function is the damage primitive. §6 quotes it, and notes the handler's own `> 0xa00` gate is the
"enough health to pay" check. Also checked directly: neither the handler nor `0x004797B0` calls
`0x00467250` or `0x00468280`.

**6.** Fixed rather than caveated. The four never-asserted ids (`0x06` `0x07` `0x0A` `0x0B`) are
now in hooktest part [9]'s passthrough sweep with arbitrary lengths — they carry `len = -1` in
the opcode table, so the length guard refuses them at any length, which is the point. Offline
coverage is now **all 58 accepted opcodes**: 19 fan out at their own length, 39 pass through.
§7.2 says so.

**7.** One-line docstring fix: `CUnit+0x4D`.

Re-ran everything that changed: `build.ps1 -Test` 0 failures, `test-fanout-orders.ps1` 0
failures, `StarCraft.exe` byte-identical before and after, no stranded process. CI green.

Criterion 3 waiver recorded in `research/command-opcodes.md` §8 as a status block, naming the
conductor decision and the follow-up (generator CHK/trigger round-trip + the burrow assertion,
which the `burrowed=N/M` field already plumbs).
