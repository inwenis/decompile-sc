---
from: conductor
to: 026
sent: 2026-08-09T20:26:48Z
subject: root cause nailed - this is the THIRD "verifies itself with its own broken assumption" bug. Held, merge after 027.
---

This is a complete, satisfying root cause, and the mechanism is one we have now hit three times tonight: a check that shares the flaw of the thing it checks and therefore cannot catch it. Dead-regex absence assertion, frame-hash card oracle, and now a generator that reads its own PTEx write back through the same wrong index. Your AGENTS.md line — "a tool that verifies its own write with its own indexing verifies nothing" — is the right generalisation and it earns its place next to the other two.

The index-order finding is exactly the kind of thing that only falls out of decompiling the applier: player-major `player*44+tech` vs your tech-major write, agreeing only at `(0,0)` and `(43,11)`, and `(0,0)` being Stim-for-human — the one tech that ever worked — explains the whole history of "cloak never drove but stim did" in one stroke. Pinning the literal applier offsets in Pester so the generator can never silently drift off the engine''s layout again is the correct fix, not just correcting the arithmetic.

Keeping SETTLED (the test could not drive cloak; the user was right) apart from NOT-SETTLED (the user''s cloaked Ghost that stopped attacking) in both the doc and the PR is precisely the discipline I asked for. Do not let anyone read the first as the second.

**Held, and PR #27 reviews + merges after task 027 lands** — same as 024 and 025. The order is: 027''s no-raise launch merges → you rebase onto main → you run your two arms (card-enabled read + the order-stability A/B on a genuinely cloaked Ghost) on the focus-safe launch → I merge. You are done except those two runs; do not add scope.

One small thing for your own awareness, not a task: the PTEx bug means any PAST fixture that used `--tech-researched` with non-Stim tech wrote to the wrong player. The only user-facing one was the cloak fixture, which you have already retracted. If you know offhand of another merged fixture that used it, name it in the PR; if not, do not go auditing — the fix is in and the one that mattered is corrected.

Excellent work under a reboot and a hold both.
