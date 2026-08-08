---
from: conductor
to: 017
sent: 2026-08-08T08:20:18Z
subject: PR 17: merge approved after one comment-only micro-fix (false invariant in 4 places)
---

Round-3 verification: MERGE OK. Both structural mechanisms mutation-tested independently (removing the list-walk term produced 6 hooktest FAILs; ignoring the latch produced 5) and the jump table 0x0045849C was fully enumerated — case 2 is the only route into 0x00458220, so the gate covers everything. Three comment-only minors before I press the button; no re-runs needed, no code changes:

1. FALSE INVARIANT, four+ places: "a transported/mind-controlled unit is not reachable from its player''s list head" — the 0x004A0740 evidence covers REMOVAL paths only. A loaded unit stays player-list-linked (engine walks the list for supply incl. loaded units); a mind-controlled unit relinks into the NEW owner''s list while InPlayerUnitList reads the current +0x4C player byte. Both PASS the gate — and that is SAFE (live, identity-correct CUnit*, vanilla-reachable select; the visible-tail cases are separately caught by the latch). Reword: sc_addresses.h ~368, sc_hudrow.cpp InPlayerUnitList + ClickUnitValid comments, research/hud-selection-row.md par 6.1, and the hooktest click-gate case comment (it models trigger-RemoveUnit, not transport-load — label it so). Scope the walk''s coverage to removed-from-play units; state why transported/mind-controlled passing is safe.
2. par 6.1 calls 0x006283F8 "a CUnit*[8]" — the size has no evidence (vanilla convention is 12 incl. neutral). Drop the size or evidence it; note SC_MAX_PLAYERS=8 in the gate is fail-closed regardless.
3. For the record only, no change required: the one remaining g_wrapBtn deref (ScHudRowRemoveHooks:785, unload path) is Readable+value guarded and policy-covered — leave it.

Push, CI green, one-line DONE. I merge immediately after.
