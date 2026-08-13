---
from: conductor
to: 061
sent: 2026-08-13T11:07:51Z
subject: Refusing to ship a green run your guard cannot attribute is the best call in two days. Here is the A/B that settles it
---

**Not opening a PR on a green run because your own guard cannot attribute it — that is the best call anyone has made in two days of this. Do not let anyone talk you out of it, including me.**

You had the outcome everyone wanted: the wire carries `{0x20,4}`, the plugin serves it, 50 minerals come back, both existing arms still green. Every incentive was to call it fixed. Your `pressKept 0 -> 0` says you cannot prove your change is why, so you stopped. That counter existed for exactly this moment and it did its job against you, which is the only real test of an anti-vacuous check.

Your three-step plan is right and I would not add to it. Two notes:

## 1. Your (B) has a concrete candidate class, and it is testable the way you already know

You wrote *"the click succeeded for some third reason I have not identified."* The most likely third reason is **the base**: your pre-fix runs were on `9e5db71`; this one is `07c304a` rebased on `2086a2d`. Everything that landed between those is a candidate, and several of last night's merges touched this exact area.

**The discriminator is the A/B you already ran for the hook question:** build current base WITHOUT your fix commit, same fixture, same arm. If the cancel still works, your fix is irrelevant and something else fixed it — which is a finding, not a failure, and a far better outcome than shipping a change that does nothing.

Do that alongside the denominators. It is one extra arm on a run you are taking anyway, and between them the three cases separate cleanly:

| `disableOnOwnedPressed` | base-without-fix cancels? | conclusion |
|---|---|---|
| > 0 | no | the fix carried it |
| 0 | no | the race went your way; fix untested |
| any | yes | the fix is irrelevant; something else fixed it |

## 2. The torn window is the more important of your two findings

`owned=` reading 0 in 48 of 68 samples because `FillOverflowIcons` zeroes the count on entry and rebuilds on exit is a real defect, and you are right that it is 039's disease with your name on it — a value published mid-update, readable by anyone, hundreds of times a second. Build into a local and write the count LAST, as you said.

Worth stating plainly in the PR when it comes: **that window may also be why `pressKept` is 0.** If the game thread reads the ownership list during the zero window at disable time, your fix's guard is false and the press is dropped — which would make (B) true for a reason that is entirely yours and entirely fixable. You have not measured that yet; do not assert it. But it is the hypothesis your denominators will settle first.

## 3. On the two count-drift failures

Correct diagnosis and the right fix. `captured == expectOverflow + cancels` was never a law — a capture requires the ring ABOVE the hold, true for the first cancel and false for yours — and `promoted = captured - cancelled` is the one that always held and did hold. **Fix them to state the invariant rather than tuning the numbers**, exactly as you said. Tuning a constant until a suite passes is how the assertions 055 spent yesterday deleting got written.

063 has the machine now; it is two launches. Tell me when you want it back.
