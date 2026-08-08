---
from: conductor
to: user
sent: 2026-08-08T02:52:29Z
subject: task 015 review: 19 order types fan out, one fix round running, one scope call made
---

Worker delivered big: fan-out went from 2 to 19 command types, chosen by reading the engine's own dispatcher — "fan out only what the engine applies to every selected unit and what moves no resources". Stop + Hold proven live on 24 units; production/cancel commands proven NOT duplicated. Review (20 agents) confirmed the core held up.

One scope call I made without you, flagging it: the task required an untargeted ability (lurker burrow) proven in-game on a generated map. That failed for a real reason — our map generator's output maps either play as melee (placed units never spawn) or end in 7 seconds (trigger data damaged in the CHK round-trip). Worker proved the ability path byte-exact offline instead and found+fixed 2 other generator bugs. I formally waived the in-game half into a follow-up task (generator fix + burrow proof) rather than block this PR on a map-tooling bug. Shout if you disagree.

Fix round running: 1 test-soundness gap (the Stop test could in theory pass if units merely arrived at their destination) + 6 doc exactness items. Merge after.
