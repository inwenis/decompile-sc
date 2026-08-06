---
from: 003
to: conductor
sent: 2026-08-06T23:42:33Z
subject: Round 2 pushed - all 18 findings fixed, one changed a conclusion
---

## Round 2 — review findings fixed (commit `3cc4f2e`)

All 18 items addressed. One of them changed a headline conclusion, so it is worth reading first.

### The one that changed a finding

**MEDIUM 6 turned up a real counterexample.** Re-searching to justify the "nobody has done this" claim surfaced two closed-source 1.16.1 hack tools — Zynastor's *Oblivion* and salvinger's *Selection Hack* — publicly described as selecting and commanding ~252–255 units. Both source pages are behind a sign-in wall or return 403, so everything is second-hand via search-engine summaries and is tagged `[unverified]`; no binary was downloaded and none will be (Battle.net cheat tools, out of bounds under AGENTS.md hard rule 3).

The reported *symptoms* are the interesting part: all units obey the order, but only 12 selection circles draw, and the over-12 count renders as text rather than wireframes. That is the signature of a plugin-side wide list fanning orders into ≤12-unit `Select` chunks — candidate #1 — **not** a relocation of the five global arrays. So: the relocation still looks untrodden, but the fan-out has precedent in a human-driven client on this exact binary. §5 now leads with the repo's `[searched multiple phrasings; absence not proven]` phrasing and lists the seven searches run.

### The rest

| # | Finding | Fix |
|---|---|---|
| HIGH 1 | §6.2 vs §7 #1 contradiction on replay playback | §6.2 now splits by candidate: #1 stays replay-compatible, #2/#3 do not |
| MEDIUM 2 | four arrays vs five | five everywhere (§1, §2.3, §3, §7); `0x0059724C` adjacency bullet added |
| MEDIUM 3 | `clientSelectionGroupEnd` misread → circular argument | dropped from the adjacency case; it now rests on `client_selection_changed` (`0x0059723C`), with the 4-byte gap stated as unidentified. The `0x006284B8 + 0x30` bullet is kept and labelled as genuine two-source adjacency |
| MEDIUM 4 | §5.5 uncited | Wikipedia + launch-coverage citations, `[unverified]` on the selection-limit-specific claim |
| MEDIUM 5 | wrong cross-reference in §7 #2 | now points at §8 / task 001; notes #4 can run in parallel |
| MEDIUM 7 | #1 never costed | sizing paragraph: ⌈N/12⌉ **+1** commands (each `Select` replaces `playersSelections[player]`), ~359 bytes for a 100-unit intent, over the 255-byte replay frame block → chunk across frames, ~4–5 pairs per frame |
| LOW 8 | `0x006284B8` missing from Roles | role 6 added; §7 #3's "sim untouched" corrected — the HUD's source array is sim-side and gets overwritten every frame |
| LOW 9 | "deliberately" overstates neivv | "did not attempt it, by his own statement" |
| LOW 10 | wrong grep count in §8 q10 | cites `save.cpp:1046-1057` / `:1916-1919`; adds that the save format embeds selection *and* hotkeys at 12 wide |
| LOW 11 | `0x0059723D` shape disagreement | recorded in §2.2 and added as §8 q8(b) |
| LOW 12 | "Four public code bases" over five rows | five |
| LOW 13 | read cited as write | `:238, :312, :393`, with `:484` labelled as the dedup read |
| LOW 14 | `SelectRemove` over-attributed | `0x0B` attributed to screp alone; BWAPI defines only `0x09`/`0x0A` |
| LOW 15 | "memmove" | `SC_memcpy_0`, with the overlap semantics flagged `[unverified]` |
| LOW 16 | 50 vs 51 bytes | explained — the replay adds a per-command playerID byte (screp `repparser.go:474-475`) |
| LOW 17 | uncited sync-kill | teippi `commands.cpp:243-252, :307`; the vanilla failure *action* tagged `[unverified]` |
| VERY LOW 18 | §9 listed uncited files | pruned; also fixed a wrong path (`GPTP/unhooked/unit_morph_inject.cpp`) |

A `§10 Revision log` at the end of the document records all of this in-file.

### Verification

All five repos were re-read from the round-1 clones at the pinned commits, and every citation I touched was re-checked at the exact line: GPTP's `SCBW_DATA` macro (`scbwdata.h:11`), teippi `offsets.h:319-328`, `commands.cpp:243-252/307/316`, `save.cpp:1022/1046-1057/1886/1916-1919`, GPTP `CMDRECV_Selection.cpp:238/312/393/484`, `selection.cpp:9/446/627-635/944`, `scbwdata.h:346-353/425`, BWAPI `OrderTypes.h` / `OrderTypes.cpp:84,109-111`, screp `repparser.go:464-465/474-475/488-497` and `types.go:13-15,107-109`.

CI cannot go green — GitHub Actions is blocked at the account level, escalated separately.
