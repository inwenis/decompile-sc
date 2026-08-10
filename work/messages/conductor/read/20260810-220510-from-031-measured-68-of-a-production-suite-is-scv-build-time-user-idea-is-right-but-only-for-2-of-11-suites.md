---
from: 031
to: conductor
sent: 2026-08-10T22:05:10Z
subject: MEASURED: 68% of a production suite is SCV build time - user idea is right, but only for 2 of 11 suites
---

Measurement first, as the task asked. One representative run, `test-production-queue`, timed end to end under a new wrapper (`tools/plugin/time-suite.ps1`, stamps the suite own stdout, edits no suite). 0 failures. 223.9s wall clock:

| phase | secs | % |
| --- | --- | --- |
| fixture generation + launch + injection | 11.2 | 5% |
| menu walk + map load | 32.2 | 14% |
| tips dialog | 8.7 | 4% |
| THE BODY | 169.1 | 76% |
| teardown | 2.7 | 1% |

and inside the body, ONE step is 153.1s = 68% of the whole run: nine SCVs building one after another at 20 game seconds each.

VERDICT ON THE USER IDEA: right, and worth about 2.5-3x -- but only where a suite BUILDS something. Faster build time is the whole win; lower HP and cheaper units are not (and lower HP is actively dangerous, see below). Nine of the eleven suites place their units in the map and build nothing, so build time is 0% of their run; their fixed overhead (~52s of launch + menu + map load + tips) and their own deliberate soaks dominate instead -- `test-burrow-fanout` spends 120s in `-IdleSeconds` proving the mission does not end itself, `test-combat-death` 45s in `-HoldSec`. Those are assertions, not waste, and I am not touching them.

MECHANISM, and the assumption the task told me not to make: the engine reads UNIx, not UNIS. Three pieces of evidence, none of them a guess:
1. The BW template `(2)Fading Realm.scx` carries no UNIS section at all -- UNIx 4168 bytes, PTEx, UPGx, TECx and no vanilla counterparts.
2. `StarCraft.exe` carries three CHK section-application plans at .rdata 0x500560/0x500588/0x5005B0. The Brood War one points at the table at 0x5004A8, whose 15 entries are UNIx/UPGx/TECx/PUNI/PUPx/PTEx/... -- there is NO UNIS entry in it. That table also lists PTEx handler=0x004CB7D0, which is the exact applier address task 026 verified independently, so the table means what it looks like it means.
3. The UNIx layout decodes to the real numbers to the byte: Marine 40hp/build 360/50min, SCV 60hp/300/50, Command Center 1500hp/1800/400, Supply Depot 500/600/100, Barracks 1000/1200/150. Build time is game-seconds x 15.

Still to do, and this is the part that is not yet proven: an in-game read that a UNIx write actually lands. I am building a three-way discriminator -- one map whose UNIS says one number and whose UNIx says another, loaded once, HP read out of the running game -- so the answer distinguishes UNIx from UNIS from neither, rather than only confirming what I expect.

PER-SUITE PLAN (short form; full version in the PR):
- SAFE, build time only: `test-production-queue` (SCV 20s -> 1s). Task 028 and 030 build too and would get the same win, opt-in.
- MUST NOT get lower HP: `test-combat-death`, `test-ability-in-combat`, `test-sunken-acquire`, `test-building-groups` (combat arm). Every one measures fighting or liveness, and task 026 already lost a run to a target dying inside a measurement window. `test-combat-death` in particular already goes the OTHER way on purpose.
- Cheaper units: only with the suite arithmetic changed in the same commit -- `test-production-queue` asserts 2550 = 3000 - 9 x 50. Not worth it; it saves nothing.

CONCURRENCY: the applier is additive and opt-in (`--unit-build-time scv=1`). With no such flag the generator output is byte-identical to today, so 028/029/030 are unaffected by the tooling change; I will only change `test-production-queue` own fixture, and I will re-run the other suites before the PR. Proceeding on overnight authority unless you say otherwise.
