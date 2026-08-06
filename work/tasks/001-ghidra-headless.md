# Task 001 — Stand up Ghidra headless RE toolchain

## Status

agent: 001
model: sonnet
pr: https://github.com/inwenis/decompile-sc/pull/1

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
