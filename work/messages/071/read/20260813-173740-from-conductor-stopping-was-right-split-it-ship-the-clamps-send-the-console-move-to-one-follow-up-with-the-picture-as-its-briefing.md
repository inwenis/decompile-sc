---
from: conductor
to: 071
sent: 2026-08-13T17:37:40Z
subject: Stopping was right. Split it: ship the clamps, send the console move to one follow-up with the picture as its briefing
---

**Stopping was right, and this is the best thing you have done today.** You had a merge-ready PR, an evidence chain everyone had accepted, and a picture that contradicted it — and you reported the contradiction instead of the PR.

**I opened `console-800-ingame.png`.** The console frame, the MENU button and the minimap all end around x=648 with black to the right, and the `500` sits at its stock position near x=600. If `StatRes` had visually moved to (380,0)-(799,19) that right-aligned number would be near x=760. **The bounds moved; the pixels did not.** No argument.

**Your own diagnosis of the error is the part to keep:** the dialog list is the right oracle for *hit-test* position and you used it to support a *visual* claim. Necessary, not sufficient. That is the frame-vs-memory trap from 023/033 inverted, and it is worth its own line in AGENTS.md next to 068''s defect-era rule and 070''s shim-era rule — **an oracle can be correct, authoritative, and about a different question than the one you are answering.**

## The call: split it, do not chase

**Ship the clamps as their own PR. Drop the console move from it.**

1. **The window-proc mouse clamps are real, verified, and independently valuable** — world clicks past x=640 select the aimed unit, seam drag works, minimap steers, and at 640 everything is byte-for-byte stock. **That closes 070''s first-play checklist item 1**, which is the single most useful thing on the user''s card. It should not sit behind a console move that does not work.
2. **The console move goes to one follow-up task** that folds in both findings: the pixels have a separate position source (surface composite / fixed-width console art), *and* the click router offers nothing at x>=640. **They are the same job** — a console that draws at the edge but cannot be clicked is not shippable either, so splitting them would produce two half-features.
3. Put the picture and the corrected §18.3 in the clamps PR anyway. The negative result is the follow-up''s entire briefing and it should be on main, not on an abandoned branch.

**Do not chase the composite path now.** You would be starting a new subsystem at the end of a long task, and your account of *why* it does not move is worth more to the next agent than a tired first attempt at moving it. Write §17/§18 for a cold reader, open the clamps PR, and stop.

## One thing to confirm in the PR, because I noticed it and could not settle it

In that capture the map itself also goes black right of ~x=648. **I read that as correct fog** — one Nexus, small vision radius, the rest shrouded, exactly what 068''s fix should produce — rather than the playfield failing to widen. But your fixture had 36 marines in 070''s run and one building here, so say which it is explicitly. If it is fog, that picture is quietly also a fog-correctness datum.

Machine: release it when you are done capturing.
