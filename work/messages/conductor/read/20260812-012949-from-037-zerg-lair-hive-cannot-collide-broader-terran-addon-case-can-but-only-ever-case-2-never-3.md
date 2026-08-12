---
from: 037
to: conductor
sent: 2026-08-12T01:29:49Z
subject: Zerg Lair/Hive: cannot collide. Broader Terran-addon case: can, but only ever case 2, never 3
---

Answered from code + research docs, no Zerg game built, per your instruction.

THE SPECIFIC CASE YOU NAMED (Lair/Hive): case 1, cannot happen, and here is why. Zerg
Hatchery/Lair/Hive never receive a Train-style command at all - units come from LARVA
morphing, and that command targets the larva's own CUnit, not the Hatchery/Lair/Hive's.
So CUnit+0x98 (the build-queue ring EngineQueueLength reads) never gets written for that
unit by any player action, in any state, upgrade or not. engineLen+overflow can never
exceed 0, so STRIP's own precondition (`hidden = engineLen+overflow-5 > 0`) can never be
true there - nothing to collide with. Sourced from how Zerg production works generally
(larva is a distinct, separately-clickable unit) plus sc_prodqueue only ever tracking units
that reach it via the 0x1F Train funnel, which a Hatchery/Lair/Hive command never does.

CAN IT HAPPEN ANYWHERE: yes, structurally, for a different reason than the one you named.
0x98 (ring) and 0xC8/0xC9 (research) are non-overlapping CUnit offsets (confirmed,
sc_addresses.h) - nothing stops both being non-empty on the SAME unit if the engine ever
sends both kinds of command to it. Candidate: a Terran Factory/Starport/Science Facility
with its addon attached (Machine Shop/Control Tower/Covert Ops/Physics Lab) trains units
into its own ring AND, I believe, tracks addon-gated research (Tank Siege Mode etc.) on
the MAIN building's own CUnit, not the addon's - the addon isn't separately selectable and
the "Upgrading:" card/portrait shown is the main building's own. I could not fully confirm
this from research/ docs alone (nothing in this repo maps addon-research to which CUnit
holds 0xC8/0xC9 for that case) and did not spin up a Factory+Machine Shop game to check,
since you said not to build a test for this class of question.

CAN IT EVER RENDER WRONG (your case 3): no, and this part I can say with full confidence,
independent of which building. ScQueueIndCompose is a strict if/else: `if (v->upgrades > 0)
return SC_QIND_UPGRADE;` is checked and returned BEFORE the STRIP branch is even evaluated,
inside the same selection<=1 block. One mode, never a blend, never two things drawn over
each other. So the ceiling on this whole class is case 2 - one wins, silently, cleanly -
never case 3.

Net: merge is safe by your own rule (2 is mergeable). Worth a follow-up task: confirm
which CUnit an addon-gated research write lands on, and if it's the main building, decide
whether STRIP should take priority over UPGRADE when both are true (or show both, which
needs actual UI room this indicator does not have). I did not change today's precedence -
it predates my fix, in ScQueueIndCompose, untouched by this PR.

038/SoleSelectedUnit: no interaction. My diff never touches sc_upgrades.cpp. ReadView() in
sc_queueind.cpp resolves the building via PortraitUnit() (SC_VA_ACTIVE_PORTRAIT_UNIT), not
SoleSelectedUnit()/activePlayerSelection - different read path entirely.
