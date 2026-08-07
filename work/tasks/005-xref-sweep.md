# Task 005 — Ghidra cross-reference sweep of the selection arrays

## Status

agent: 005
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/6

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task005 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task005-xref-sweep.
- Task-file edits, reports, messages: directly in C:/git/decompile-sc (main
  checkout, no commits there — conductor commits; you are the only writer).
- NEVER edit tracked content in the main checkout.
- Destructive/irreversible actions beyond your own worktree (deleting user
  files, force-push, merging PRs, killing processes) → stop, ask in your tab
  or message the conductor first.
- NEVER delete/overwrite anything under C:/git/decompile-sc/work/messages/
  (2026-07-17 data-loss incident class — real user messages live there).
- C:/git/conductor and C:/git/conductor-task* are ANOTHER LIVE SYSTEM (a
  separate orchestrator with in-flight agents and real user messages).
  NEVER read, modify, cd into, or run git/gh against them — off-limits
  absolutely (guard hooks also enforce this). Your world is
  C:/git/decompile-sc and your own worktree only.

## Game-file rules (project hard rules)

- NEVER commit game binaries, MPQ archives, extracted assets, or anything
  derived from them that reproduces game content. The repo tracks findings
  and tooling only.
- The local game copy lives at an ignored path (game/) and is READ-ONLY to
  workers.
- Never point a modified binary at Battle.net or any online service. Offline
  and single-player only.
- Every claimed address/offset/struct must carry evidence: how it was found
  and how it was verified. No guessed offsets in research/.

## Messaging

- Your inbox: `C:/git/decompile-sc/work/messages/005/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 005 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

First real binary analysis of the project. Using our own Ghidra pipeline against
StarCraft 1.16.1, answer questions 1–3 of `research/selection-cap.md` §8: produce a
**cross-reference table** of every instruction that touches the selection globals, an
**immediate-constant sweep** of the selection functions, and an **adjacency confirmation**
of what actually sits around those arrays. Then **calibrate** our pipeline by comparing its
decompiled output for a few functions against GPTP's published C reimplementations of the
same addresses. Deliverable is documentation and tables — never game code.

## Context

- **Target binary**: `C:\sc-work\1161-base\StarCraft.exe` — the disposable WORKING COPY.
  Never touch `C:\sc-install\Starcraft` (the user's pristine, playable install). If the
  working copy is missing or its hash is wrong, regenerate it with
  `C:/git/decompile-sc-task002/tools/make-working-copy.ps1 -Force` rather than improvising.
  Expected `StarCraft.exe` sha256
  `AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46` — verify before you
  trust any result, and state in your report that you did.
- **The Ghidra pipeline is NOT on main yet.** It lives on an unmerged branch. Use it
  read-only from `C:/git/decompile-sc-task001/tools/ghidra/`:
  - wrapper: `C:/git/decompile-sc-task001/tools/ghidra/analyze.ps1`
  - the Ghidra install itself is under that same directory (gitignored there)
  - read `C:/git/decompile-sc-task001/tools/ghidra/README.md` first — it documents the
    pinned version, the `-FunctionAddress` requirement for symbol-less binaries, and the
    manifest that is the run's only trustworthy success signal.
  You may READ from that worktree. Do NOT write to it, commit in it, or modify it. Your own
  work happens in `C:/git/decompile-sc-task005`.
- Recent fixes you benefit from: per-run project dirs (so concurrent runs no longer collide),
  a manifest that makes a failed run fail loudly instead of silently reusing stale output,
  an explicit WARNING when an address resolves to an *enclosing* function rather than an
  entry point, and `-SkipListing` for iterative work. Use `-SkipListing` for per-function
  queries; you do not need a full listing every time.
- **Read `research/selection-cap.md` first** — it is on the unmerged branch
  `C:/git/decompile-sc-task003/research/selection-cap.md`. Read it there. Its §2.2 table and
  §4 function tables are your input list; its §8 is literally the contract for this task.
  Note it is being revised concurrently; work from the addresses, which are stable.
- Every address in that document is *asserted by a public project*, not verified against the
  binary. **You are the first to check them.** Treat a mismatch as a finding, not a mistake
  to paper over — a wrong address inherited from prior art is exactly what this task exists
  to catch.

## Hard rules (read twice)

1. **Never modify the pristine install.** Read-only, and you should not need it at all.
2. **Never commit game content.** This is subtler than it sounds for this task: a full
   disassembly listing and a large verbatim decompiled function ARE derived game content.
   Commit **findings** — address tables, xref tables, struct layouts, constant inventories,
   short illustrative snippets of a few lines where genuinely needed to make a point. Do NOT
   commit listing dumps, whole decompiled functions, or bulk exported output. Ghidra output
   goes to a gitignored scratch path.
3. **Every claim carries evidence**: the instruction address, how it was found, and how it
   was verified. No guessed offsets. Mark anything uncertain `[unverified]`.
4. Offline static analysis only. Do not launch the game in this task.
5. Do NOT weaken `scripts/merge-task.ps1`, and do NOT merge your own PR.

## Steps (suggested)

1. Verify the working copy's hash. Confirm the Ghidra pipeline runs at all by reproducing the
   README's documented example on a benign PE. Only then point it at StarCraft.exe.
2. Import and auto-analyze `StarCraft.exe` once. Expect this to take a while and expect the
   language to resolve as a 32-bit x86 Windows PE with no PDB — record what Ghidra actually
   reports (`Using Language/Compiler:` line, image base, entry point) rather than assuming.
3. **§8 Q1 — cross-reference sweep.** For each of `0x00597208`, `0x0059724C`, `0x006284B8`,
   `0x006284E8`, `0x0057FE60`, `0x006284B6`, `0x0059723D`: list every instruction that
   references it, with the containing function. This list IS the size of the relocation work,
   so completeness matters more than commentary. Deliver as a committed table.
4. **§8 Q2 — immediate-constant sweep.** In the functions named in `selection-cap.md`
   §4.1–§4.5, find every immediate `0x0C` (12), `0x0B` (11), `0x30` (12×4), `0x2C`, `0x12`
   (18) and the hotkey array size, with the instruction address and its role: loop bound,
   index scale, array size, or comparison. Role matters — a comparison is a policy check, an
   index scale is structural.
5. **§8 Q3 — adjacency confirmation.** Determine what actually occupies
   `0x00597238`–`0x0059724C`, the bytes after `playersSelections` ends, and the bytes after
   `selection_hotkeys` ends. The recon doc's own argument here was found to be partly
   circular, so this is a real open question: is there slack, or are these arrays hard against
   named neighbours? Specifically resolve the 4-byte gap between `0x00597238` and
   `0x0059723C`. Answer per array — it decides relocate-vs-extend independently for each.
6. **Calibration.** Decompile a few of these and compare against GPTP's published C
   reimplementations of the same addresses (GPTP has reference implementations for most of
   them, which makes this a verification exercise rather than a blind decompile):
   `0x004C2750` (CMDRECV_Select), `0x004C2560` (CMDRECV_ShiftSelect), `0x0049AF80`,
   `0x0046F0F0` (SortAllUnits), `0x004C0860` (CMDACT_Select). Report where our output agrees
   with GPTP and where it does not. **Disagreements are the most valuable output of this
   task** — they mean either our pipeline is wrong or the public prior art is.
7. Write `research/binary-selection-map.md` with the above. Cross-link
   `research/selection-cap.md` (note it may not be merged yet — link by path). Include a
   short "confidence and method" section: what you verified directly, what you inherited,
   what remains open.
8. If the analysis is too large to finish cleanly, deliver Q1 and Q3 complete and say plainly
   what is unfinished. A complete, trustworthy partial answer beats a rushed full one.

## Acceptance criteria

1. Working-copy hash verified and stated; pristine install untouched.
2. A committed cross-reference table for all seven globals, with per-instruction addresses
   and containing functions. Gaps stated explicitly rather than left implied.
3. A committed immediate-constant inventory with each constant's ROLE identified.
4. An adjacency answer per array, resolving the 4-byte gap question, with evidence.
5. Calibration results against GPTP for at least three of the five functions, with agreements
   AND disagreements reported. Any inherited address that does not check out is called out
   prominently.
6. Nothing binary or bulk-derived committed: no listings, no whole decompiled functions, no
   `.gpr`, no game files. `git status` verified clean of these before commit.
7. PR opened, link in Status.pr. Note that CI cannot currently run (GitHub Actions is blocked
   at the account level, escalated to the user) — that is expected and is not your problem;
   do not wait on it.

## ROUND 2 — review findings to fix (added by conductor 2026-08-07)

An adversarial verifier re-derived your headline claims **from raw bytes, hand-decoding
without using any of your tooling**, then separately re-ran your pipeline. Result: the
analysis held. Your `sweep.ps1` chain regenerated `selection-xrefs.tsv` **byte-identically**
(5008 → 5082 functions exactly as documented), 17 randomly sampled TSV rows across all three
files every one decoded to the exact claimed instruction, and all 35 inherited addresses
resolved to entry points. §3's occupancy numbers reproduced exactly. This is strong work.

**Your §7.1 claim is upheld: `selection-cap.md` §4.4 is wrong and must be corrected.** The
`CMP BL,0xc` gate at `0x0049A857` was confirmed by independent hand-decode. Fix that in the
merged doc too — see item 11 below.

Fix the following on your branch and push. Your PR stays open; do not open a second one.

**HIGH 1 — classifier bug puts the WRONG value on your most load-bearing site.**
`selection-immediates.tsv` row `0x004C275A` says `role=struct-or-stack-offset`,
`capRelevant=False`. Your own §4 table says `comparison`, cap-relevant. That is a direct
doc↔data contradiction. Cause: when an instruction has both a memory displacement and an
immediate, the classifier prefers the displacement — `CMP byte ptr [ESI + 0x1],0xc` picked the
`0x1` and lost the `0xc`. Impact: anyone filtering `capRelevant=True`, which is the obvious
programmatic use of the file, **misses the CMDRECV_Select packet-count cap** — the exact site
your §5.4 uses to answer §8 q8. Fix: classify by the immediate when the watched value IS the
immediate operand. Headline becomes **44 of 111**, not 43. Re-check the whole file for other
instances of the same pattern.

**HIGH 2 — the `playersSelections` row stride (×12) appears in NEITHER table.** It is encoded
as `LEA r,[r+r*2]` (×3) combined with a `*4` scale or `SHL r,4`, at **at least 12 sites**:
`0x004966D1, 0x00496A89, 0x0049A225, 0x0049A241, 0x0049A757, 0x0049A76F, 0x0049A869,
0x0049AFBB, 0x004C2659, 0x004C26B0, 0x004C27D7, 0x004EEDD0`. These are invisible to the xref
sweep (they reference no address) and to the immediate sweep (they contain no immediate) — yet
**every one of them must change to widen the array**. This is a genuine completeness gap in
the deliverable's core purpose: the relocation work list.

Your §1.3 states the residual gap as base-in-register / base-in-global. It does **not** cover
encoded strides. Fix: widen §1.3 to name this class explicitly, and add a stride-site table.
The `8D` LEA forms paired with `0x6284E8` materialisation are mechanically findable, so this
should be a sweep, not a manual list.

**MEDIUM 3 — `0x180` (384 = `sizeof(playersSelections)`) is missing from the watched values.**
Confirmed as `PUSH 0x180` immediately before `0x6284E8` is materialised, at `0x004C2D1D`,
`0x004D0139`, `0x004D0685`. You already watch `0x30` (48 = a 12-pointer array), so byte sizes
were in scope — this is the same class of value. Note `0x004C2D1D` is not save/load, so your
§8 q10 deferral does not cover it. Add `0x180` and re-run `ImmediateSweep`.

**MEDIUM 4 — §3.1 prose cites the wrong address.** You write `004C38FA CMP EBX,0x597238`. At
`0x004C38FA` the binary actually has `CMP byte ptr [0x0059723d],0x1`; the real
`CMP EBX,0x597238` is at **`0x004C38F2`**, 8 bytes earlier. Your committed TSV has it right —
this is a prose transcription error only. Fix the prose.

**MEDIUM 5 — "called from 71 sites" is wrong and is your only unsourced number.** True value
is **73** (72 `CALL` + 1 tail `JMP`), confirmed two independent ways: a raw rel32 scan and your
own `RegionProbe`'s `refCount 73`. Your conclusion is unaffected — still one function to fix,
not 73 — but this is the one count in a document that claims full sourcing with no traceable
source. Fix the number and cite `FuncProbe`'s callers column, or commit that output.

**MEDIUM 6 — §4's role table does not match the file it summarises.** The table lists 9 roles
summing to **112**; the file has **111** rows across **8** roles. The 9th role, `command-id`
(count 1), does not exist in the TSV — row `0x004C0A9B` is classified `struct-or-stack-offset`
there, which is also wrong for the same reason as finding 1 (`0xb` is the immediate, not the
displacement). Either add a real `command-id` role or correct the table.

**MEDIUM 7 — §2 over-reads the element-offset column.** "12 separate patch sites per array" is
not what the binary shows: only **7** distinct `clientSelectionGroup` element addresses are
literally encoded anywhere (`+0,4,8,12,16,20,44`); offsets 24–40 have zero encoded dwords.
Their attribution to slots 6–11 comes from one 6-way-unrolled loop where Ghidra resolved a
propagated register base. Only 63 of 119 rows carry a literal address at all. Your per-row data
is honest — the summary sentence is the problem, and it is being used to justify a relocation
strategy. Fix: say "≥7 literally-encoded slot addresses plus resolved register-base accesses",
and mirror the propagation caveat you already give in §3.5.

**LOW 8 — the §1.2 code-recovery seed list is not committed**, so the documented commands do
not reproduce your result in order. The verifier re-derived it in one line (the `UNCOVERED` +
`.text` rows from pass 2, 31 seeds) and got a byte-identical table, so this is mechanical.
Commit `specs/selection-code-recovery.spec`, or have `build-xref-table.ps1` emit it.

**LOW 9 — watched value `0x1B00` produced zero rows and the absence is not reported.** You
report `0x2C`'s absence explicitly; do the same here. Only 7 of 9 watched values occur.

**LOW 10 — 3 of the 49 `playersSelections` rows are semantically `activePlayerSelection`
end-pointer comparisons** (`ADD reg,4` + `CMP reg,0x6284E8` at `0x0049A303`, `0x0049AE75`,
`0x004C3B62`). §3.3 explains the shared boundary so this is a labelling nuance, not an error —
but say so in the table's notes.

**11 — CORRECT THE MERGED RESEARCH.** `research/selection-cap.md` is now on main and your
branch has main merged in, so fix it on your branch — the correction belongs with the evidence
that produced it. Its §4.4 claims `getActivePlayerNextSelection` is "bound-agnostic — it
terminates on NULL, not on a count" and calls that "the single most encouraging finding in this
document". That is false on this binary. Rewrite it to reflect the `CMP BL,0xc` gate, state
that it is one function to fix rather than 73 call sites, and cross-link
`binary-selection-map.md` as the source. While there, correct anything else your binary work
overturned — including §8 q5 and q8, which you resolved. Add a line to that doc's revision log.

Do NOT merge your own PR. Message the conductor when pushed.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/005-xref-sweep.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
