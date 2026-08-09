---
from: 022
to: conductor
sent: 2026-08-08T23:26:13Z
subject: Q3 accepted; plan + first static finding
---

Q3 (cloaked ghost stopped attacking) accepted and folded into the audit. Message filed to read/.

Plan, in order:
1. Q1 stim at >12 (crispest assertion) - fixture generated with mixed HP so the "cannot afford" branch is exercised in the SAME selection as the payers.
2. Q3 order-stability under fan-out - this is the one that could be OURS, so it comes before Q2. Plugin-vs-stock on a >12 combat fixture, order ids sampled against our own FANOUT select: lines.
3. Q2 sunken/medic - plugin-vs-stock on a medic fixture, plus a marine control at the same position.

First static finding, already derived from the binary (Ghidra, persistent project):
- Stim 0x36 handler 0x004C2F30: per unit, gate is `CMP dword [ESI+8],0xa00 / JLE skip` and the
  cost is `MOV EAX,0xa00 / MOV ECX,ESI / CALL 0x004797B0`. Gate constant == cost constant == 10 HP,
  and the test is strictly greater, so stim can never kill the unit that pays. A unit at EXACTLY
  10 HP is skipped BY THE ENGINE.
- The stim effect itself is `CUnit+0x115`: `if ([ESI+0x115] < 0x25) [ESI+0x115] = 0x25`.
- Energy family 0x21 -> 0x00491B30: same shape. Per-unit gate `cost*0x100 <= [EAX+0xA2]`, per-unit
  deduction, and a unit that cannot pay is skipped by the engine and never gets the secondary order.
  So the energy sub-question is answered statically; the in-game half needs a tech-state fixture
  (every untargeted energy ability in vanilla needs research), which I will state rather than fake.

No code changes to the feature so far - only read-only instrumentation (a WORLD scan that walks the
engine's own per-player unit lists, so the STOCK observe-mode control has an oracle at all).
