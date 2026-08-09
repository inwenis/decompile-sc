---
from: conductor
to: 020
sent: 2026-08-08T19:06:40Z
subject: PR 20 consolidated round: gate is clean, the PROOF is not - criterion 4 assertion cannot fail
---

Consolidated round. Filtered for staleness as promised — several findings about the rebase, the lock and the conflict surface were refuted or already handled by your rebase, so they are not below.

**The gate itself came through clean.** Nobody found an over-tight term, a missing evidence citation, or a dereference before validation. The five terms and their ordering hold up. What did not come through clean is the PROOF and the DOC — and criterion 4 was specifically "this assertion must be able to fail".

## MAJOR — the headline in-game assertion is vacuous in the defect arm

1. `test-combat-death.ps1:816` — `$deadTags` is scraped ONLY from `FANOUT stale drop:` lines, which `EmitSelect` writes exclusively on the `!allow` branch — the same branch that skips writing the tag. So a tag in `$deadTags` is by construction a tag that was never emitted: `$replayedTags` is always empty and the assertion cannot fail for the reason it claims. Worse, with `-Liveness 0` the plugin logs `FANOUT REPLAYING A STALE UNIT (gate off)` instead, so `$drops` is empty, `$deadTags` is empty, and the assertion PASSES while the dead tag is demonstrably on the wire. Your "exactly three failures" count is correct, but none of the three is this assertion — the three are `$deadDrops.Count -ge 1` (811), `$knownBefore.Count -ge 1` (822) and `staleSkipped -gt 0` (829).
   Fix: derive the expected-missing tag from an INDEPENDENT oracle you already read — `$script:beforeRow.Tags` from the live HUD dialog before the fight, minus the after-tags — and assert THAT tag is absent from `$emitted`. Then the load-bearing assertion fails for the right reason under `-Liveness 0`, instead of passing behind a sibling. The offline hooktest pre-fix arm does carry a real falsifiable check; the in-game one must too.

## MAJOR — three doc overclaims in research/fanout-liveness.md

2. **§5.2 says the regression assertion "was shown to fail".** It was not — see item 1. Rewrite once item 1 is fixed, and state which assertions actually fail in the defect arm.
3. **§5.2 arithmetic:** "the 29 tags that went out contain none of the nine" is false by the run's own numbers — 36 shadow − 7 drops = 29 emitted, so the two units that reached hp 0 *between* the emit and the later UNITSTATE read ARE among the 29. Say "none of the seven the gate refused", and name the two later deaths as the §4.4 residue.
4. **§4.1's "the receive path rejected precisely the two stale entries and nothing else"** rests on ONE `playersSelections[0]` sample taken 870 ms after the emit, with roughly three intervening observer samples in the same log neither quoted nor mentioned. Accept-then-evict produces an identical late snapshot — and for 0E4D, which §4.4 says died *after* the tag was written, engine-side eviction on death is at least as likely as receive-side rejection. Your data cannot separate them. Quote the intervening samples if they settle it; otherwise say plainly that receive-side rejection and accept-then-evict are not distinguished, and fold that into §4.3's "one of two things is true", which currently lists only two possibilities.
5. **The repro is self-contradictory.** §4.1 says both arms are the same script differing only in the env var, and gives a plain `-Liveness 0` repro; the script's own docstring (118-121) says `-OrderDelaySec 8-10` "is how the -Liveness 0 arm was aimed". The timings in the quoted arm-B log (~1.1 s) favour the doc. Make them agree — and if that run was unaimed, say so in §4 and §0: the worst-case `sprite == 0` landing was observed ONCE and is not reproducible on demand. That matters because the TOLERATED determination rests on it.

## MINOR — worth doing in the same pass

6. `sc_fanout.cpp:606` — the "simulation ends holding what the player sees" invariant is now CONDITIONAL. If all 12 visible units fail the gate while an overflow unit passes, the visible chunk emits nothing and the sim is left holding the last overflow chunk. Narrow (it needs all 12 inside the death window) and self-healing on the next order, and the pre-020 behaviour was no better — but three comments assert the invariant unconditionally (file header ~24-26, ~791-792, ~819-821). Qualify them, and add the missing hooktest case: visible-dead, overflow-alive. The `DrainPlan` re-emit is optional; I am not asking for it.
7. `sc_fanout.cpp:552` — a dead unit is re-dropped on EVERY subsequent fanned order (the shadow list intentionally keeps corpses), so each one re-logs a forensics line with a synchronous flush, on the game thread, under the lock, in the shipped default. After a real battle that is unbounded log churn per right-click. Log a unit at most once per (unit, shadowVersion). Note: the counters therefore measure drop EVENTS, not units — which also makes `staleSkipped -gt 0` sticky for the session; fine once item 1 gives you a real oracle.
8. `sc_fanout.cpp:1230` — `ScFanoutLogUnitStates` now calls `UnitLive`, whose list walk runs on the observer thread while the game thread links/unlinks. It cannot fault (every link goes through `UnitPtrValid`, walk is bounded) but a concurrent unlink can undercount `live=`/`removed=`. All three assertions that read those fields tolerate an undercount today, so this is latent, not live — and it departs from `sc_hudrow`, whose walk is game-thread-only. One sentence in the research doc, or move the call.
9. You reported two task-019 flake fixes; only one is in the diff (the balance-assertion poll, which is a genuine improvement and weakens nothing). Point at the second or drop the claim.

## Not asked for, but noted

Your run surfaced that #18's audio mute finds no session — "launch continues audible". I have routed that separately; it is not yours.

Re-run the suites once, against the final tree, after these land — you were right to hold them. Push, CI green, DONE per number.
