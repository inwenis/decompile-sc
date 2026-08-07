# Task 001 — Stand up Ghidra headless RE toolchain

## Status

agent: 001
model: sonnet
pr: https://github.com/inwenis/decompile-sc/pull/1
merged: 2026-08-06

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task001 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task001-ghidra-headless.
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

- Your inbox: `C:/git/decompile-sc/work/messages/001/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 001 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

A reproducible Ghidra **headless** analysis pipeline exists in the repo and is proven
working. Given the path to a 32-bit x86 PE, it imports the file, runs auto-analysis, and
exports both a disassembly listing and decompiled C for a named function — driven from a
single committed wrapper script, no GUI clicks. This is the analysis backbone for the
StarCraft 1.16.1 reverse-engineering work that follows. The Ghidra install itself and any
test binary are NOT committed — only the wrapper, the headless script, and docs.

## Context

- No RE tooling is installed on this machine yet. `setup.ps1` reports a JDK is present and
  Ghidra is absent. `research/prior-art.md` (already in the repo) recommends Ghidra
  headless for this target class and notes no public StarCraft .idb/.gzf exists — we build
  our own analysis from scratch.
- The eventual target is StarCraft **1.16.1** `StarCraft.exe`: a ~2.7 MB 32-bit x86 PE,
  no debug symbols, non-standard/legacy toolchain. The pipeline must handle exactly that
  class. That binary is NOT installed yet and is NOT yours to fetch — prove the pipeline
  on a **benign** 32-bit PE instead (e.g. a small stock Windows system DLL copied into
  your worktree, or any non-game 32-bit exe already on the machine). Do NOT use any
  StarCraft/Blizzard file, and commit no binary.
- Ghidra install is large (~1.2 GB). Put it under a gitignored path. `.gitignore` already
  ignores `ghidra_projects/`, `*.gpr`, and Ghidra project dirs; add whatever install path
  you choose to `.gitignore` too. A Ghidra project directory embeds the analyzed binary —
  never commit one.
- Version-PIN the Ghidra release you install (record exact version + download URL + hash
  in the docs) so this is reproducible on a fresh machine.

## Steps (suggested)

1. Ensure a compatible JDK is available (Ghidra 11.x needs JDK 17+/21). If `setup.ps1`'s
   JDK is too old, install one; record the version.
2. Download a pinned Ghidra release, verify its hash, extract to a gitignored path
   (e.g. `tools/ghidra/ghidra_<ver>/` with the versioned dir ignored).
3. Write a committed wrapper `tools/ghidra/analyze.ps1` (thin, `#Requires -Version 7`)
   that invokes `analyzeHeadless` on a given PE: creates/opens a throwaway project under a
   gitignored dir, imports the PE, runs analysis, and runs a headless post-script.
4. Write the headless post-script (Ghidra Python/Java) that exports (a) a disassembly
   listing and (b) decompiled C for a function selected by name or address, to text files.
5. Prove it on a benign 32-bit PE. Capture the exact command and a short snippet of the
   disassembly + decompiled-C output as evidence.
6. Document setup + usage in `tools/ghidra/README.md`: pinned version, install path,
   JDK requirement, the one command to analyze a PE, and the known extra steps a
   1.16.1 PE will need (correct image base, no-PDB, 32-bit x86 language id).
7. Commit ONLY: `analyze.ps1`, the headless script, `tools/ghidra/README.md`, and the
   `.gitignore` addition. No Ghidra install, no test PE, no project dir.

## Acceptance criteria

1. A committed, documented headless wrapper analyzes a 32-bit PE and emits disassembly +
   decompiled C for a named function with a single command — no GUI.
2. Demonstrated on a benign (non-game) 32-bit PE; the command and an output snippet are in
   the PR (or report). No StarCraft/Blizzard file used.
3. `tools/ghidra/README.md` records the pinned Ghidra version, hash, install path, JDK
   requirement, and the specific settings a 1.16.1 32-bit x86 PE will need.
4. Nothing binary committed: no Ghidra install, no test PE, no `.gpr`/project dir. The
   install path is gitignored. PR opened, link in Status.pr.

## ROUND 2 — review findings to fix (added by conductor 2026-08-07)

Your PR #1 is open and the pipeline was independently re-verified: install, hash (three
ways), both selector paths, paths-with-spaces, and the analyzeHeadless-exits-0-on-postscript
-error behaviour your guard defends against all reproduced. The core deliverable is sound.

You were spawned fresh into the same worktree (`C:/git/decompile-sc-task004`'s sibling
`C:/git/decompile-sc-task001`, branch `task001-ghidra-headless`) because the previous session
went idle. Your branch and PR already exist — do NOT start over, do NOT open a second PR.
Fix the items below on that branch and push. A detailed copy of this list is also in your
inbox at `C:/git/decompile-sc/work/messages/001/inbox/`.

**HIGH 1 — stale output causes a silent FALSE SUCCESS.** `analyze.ps1:136,140`:
`$decompPathGlob = "$base.*.c"` matches ANY `.c` left in `OutDir` by a previous run, for ANY
function. Reproduced with the DEFAULT OutDir: run 1 `-FunctionName DllCanUnloadNow` wrote its
`.c`; run 2 `-FunctionName TotallyBogusFn_E` made Ghidra log `REPORT SCRIPT ERROR: Function
not found`, yet `analyze.ps1` printed `done.` and exited 0 because run 1's file still matched.
This defeats the exact guard your comment at `:132-133` claims to provide, and the intended
StarCraft workflow is many `-FunctionAddress` runs into one OutDir — so you WILL read a
previous function's decompilation believing it is the current one.
Fix: snapshot the pre-run set (or run start time) and require a new/newer file; better, have
the Java script emit a manifest naming the resolved function + entry point and assert on it.

**HIGH 2 — `-ImageBase` is a documented NO-OP on PE files.** `analyze.ps1:126` passes
`-loader-imagebase`; `README.md:119` documents it as the way to force the base. Ghidra's own
`analyzeHeadlessREADME.html` lists that option under **ElfLoader** only; the PeLoader option
list does not include it. Reproduced: `-ImageBase 0x400000` on a PE logged
`WARN Skipping unsupported -loader-imagebase argument` and the listing still began at the
original base — while the wrapper reported success. Image-base handling is one of the three
things this deliverable must get right for 1.16.1, and cross-referencing against a wrong base
would poison our address work.
Fix: drop `-ImageBase`, or implement it properly (`currentProgram.setImageBase(addr, true)`,
or `-loader BinaryLoader -loader-baseAddr`). At minimum hard-fail on that warning. Correct
README §3 to state plainly that a PE image base cannot be forced via a loader option.

**MEDIUM 3 — decompile failure still writes a `.c`, so the wrapper reports success.**
`ExportListingAndDecompile.java:104-110` writes `// decompile failed for ...` and returns
normally; the file exists, so `analyze.ps1:140` is satisfied. Realistic on a 1.2 MB
StarCraft.exe with the hardcoded 60s timeout. Fix: throw instead, or reject a `.c` whose first
line starts with `// decompile failed`. Expose the timeout as a parameter.

**MEDIUM 4 — fixed project dir/name breaks concurrent runs and wedges after an interrupt.**
`analyze.ps1:107,115` use a fixed dir + project name `analyze`, and `:108` unconditionally
`Remove-Item -Recurse -Force` on it. Two concurrent runs: the second died with
`LockException: Unable to lock project`. A killed run leaves an orphaned JVM holding the lock,
and the NEXT run then dies on `analyze.lock~ ... being used by another process`. Multiple
agents work concurrently here, so this will happen. Fix: per-run unique project dir/name
(PID or GUID), removed in a `finally`; catch the Remove-Item failure and rethrow with
actionable text.

**LOW 5 — address selector silently falls back to the enclosing function.**
`ExportListingAndDecompile.java:69-72`: `getFunctionAt`, else `getFunctionContaining`. An
address slightly off, or pointing mid-function, silently yields a DIFFERENT function. We will
feed addresses from third-party hook lists that may not be exact entry points. Fix: always
print the resolved function name AND entry point, and warn explicitly when the fallback was
used.

**LOW 6 — Ghidra's `launch.bat:250-252` runs `pause` on failure**, so a human running your
documented command in a normal terminal hangs on any Ghidra error. Fix: redirect stdin
(`$null | & $analyzeHeadless @headlessArgs`).

**LOW 7 — name lookup takes the first match silently** (`ExportListingAndDecompile.java:76-83`).
Duplicates (thunks, `__imp_` variants) resolve arbitrarily. Prefer `getGlobalFunctions(name)`
and error on ambiguity.

**LOW 8 — no `-cspec` passthrough.** Add a `-CompilerSpec` parameter mapped to `-cspec`.

**LOW 9 — README leaves 546 MB of dead weight**: the install steps never say to delete
`ghidra_12.1.2_PUBLIC_20260605.zip` after extracting. Add that. Also consider a `-SkipListing`
flag — you regenerate the full listing every run (724 KB for a 60 KB DLL; roughly 30 MB
rewritten per single-function query on StarCraft.exe).

**CONDUCTOR'S OWN ERROR — please correct a wrong number you inherited.** I wrote "~2.7 MB"
for StarCraft.exe into your original contract and it reached your README. Verified real
figures: `StarCraft.exe` **1,220,608 bytes (1.16 MB)**, `storm.dll` 409,600, `battle.snp`
557,310 — total code surface ~2.2 MB. Fix the README. This repo's premise is evidence-cited
claims, so a wrong number in a doc matters more than its severity suggests.

**Do NOT** weaken `scripts/merge-task.ps1`. **Do NOT** merge your own PR. Message the
conductor when pushed.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/001-ghidra-headless.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
