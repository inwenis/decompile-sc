# Task 008 — C++ toolchain, DLL injection, and runtime read of selection state

## Status

agent: 008
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task008 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task008-plugin-toolchain-inject.
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

- Your inbox: `C:/git/decompile-sc/work/messages/008/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 008 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Get **our own code running inside StarCraft 1.16.1**, and use it to **read the selection state
at runtime** — read-only, no writes, no behaviour change. Three things must end up true: a
pinned 32-bit C++ toolchain exists and is documented; a DLL of ours loads into the game
launched from the working copy without breaking it; and that DLL logs the live contents of the
selection arrays we mapped statically last night, so we can confirm those addresses are right
**while the game is actually running**.

This is rung 1 of 3 toward the user's goal (rung 2: intercept selection input and keep a
plugin-side list; rung 3: fan out orders into ≤12-unit chunks so more than 12 units obey a
single command). Do **not** attempt rungs 2 or 3 here. A clean, proven rung 1 is the whole job.

## Why the read-only step is the valuable part

Every address in `research/binary-selection-map.md` was verified *statically* — the instruction
exists, it references what we claim, the neighbours are identified. None of it has been checked
against a **running** process. Reading `clientSelectionCount` and `clientSelectionGroup` while
you select units in-game and seeing them agree is the cheapest possible way to find out that a
mapping is wrong. Discovering that during a read costs nothing; discovering it during a write
costs a corrupted game state and a confusing debugging session.

## Context

- **No C++ compiler exists on this machine.** `setup.ps1` confirms: no MSVC `cl`, no `gcc`, no
  `clang`. Python 3.11, Node, and a JDK are present. Installing and pinning a toolchain is part
  of this task. It must produce a **32-bit (x86) DLL** — the game is a 32-bit process
  (`Machine = 0x014C`, confirmed in `research/pe-anatomy.md`). A 64-bit DLL cannot load into it.
  Pin the toolchain the way `tools/ghidra/README.md` pins Ghidra: exact version, source, hash
  where practical, and install path **outside every worktree** (see the shared-install rule in
  that README — a gitignored install inside a worktree is destroyed when the worktree is pruned,
  which has already cost us once).
- **Injection vector — we already have a proven one, with a catch.** `research/launch-baseline.md`
  established that `storm.dll` loads `ddraw.dll` dynamically via `LoadLibraryA`, so Windows'
  application-directory-first search order picks up a `ddraw.dll` placed next to
  `StarCraft.exe`. That is how the bundled windowed-mode helper works, and we tested it.
  **The catch:** that same slot is what windowed mode uses. If you take the slot, you must
  chain-load — forward to the real system `ddraw.dll` (32-bit, in `SysWOW64`) and/or to
  `WMode.dll` — or you will break rendering, windowed mode, or both. Evaluate this against
  alternatives (a launcher that starts the process suspended and injects; a different proxied
  DLL) and justify your choice. Prefer the option that leaves windowed mode working, because
  every later rung needs fast visual iteration.
- **Addresses you need are already committed and verified.** From
  `research/binary-selection-map.md` and `research/data/selection-xrefs.tsv`:
  `clientSelectionGroup` `0x00597208` (`CUnit*[12]`), `clientSelectionCount` `0x0059723D`,
  `activePlayerSelection` `0x006284B8`, `playersSelections` `0x006284E8` (`[8][12]`),
  active player id `0x0051267C`. Image base is `0x00400000`; confirm the module actually loaded
  there at runtime rather than assuming (ASLR/relocation would shift everything, and that is
  exactly the kind of thing this task exists to discover).
- Target: `C:\sc-work\1161-base\` — the disposable working copy. `tools/make-working-copy.ps1
  -Force` resets it to byte-identical in ~3 seconds if you break it.

## Hard rules

1. **Never modify or even read from `C:\sc-install\Starcraft`.** That is the user's pristine,
   playable install. All work happens on the working copy.
2. **Offline and single-player only.** Never connect to Battle.net or any online service, never
   enter multiplayer, never enter a CD key. A modified client must never touch an online
   service — this is a standing project rule, not a preference.
3. **Read-only this task.** Your DLL must not write to game memory, patch code, or alter
   behaviour. Observation only.
4. **Commit no game content**: no binaries, no MPQs, no assets, no memory dumps, no captured
   log files containing game data. Log output goes to a gitignored scratch path. You commit
   source, build scripts, and documentation.
5. **Clean uninstall must work**: removing your DLL returns the working copy to a normal game.
   Demonstrate it.
6. Do not merge your own PR. Do not touch `scripts/merge-task.ps1`.

## Steps (suggested)

1. Choose, install and pin a 32-bit C++ toolchain. Record version, install path (outside
   worktrees), and the exact build command. Prove it by building a trivial 32-bit DLL and
   confirming its PE machine type is `0x014C` — do not assume the flag did what you meant.
2. Decide the injection vector, with the windowed-mode conflict above resolved. Write down why.
3. Build the minimal DLL that proves our code runs inside the process: on attach, write a line
   to a log file at a gitignored path with the process id, the module base address it observes,
   and a timestamp. Launch the game from the working copy, confirm the line appears, close the
   game cleanly.
4. Confirm the game still works normally with the DLL present — it launches, renders, reaches
   the menu, and windowed mode still behaves as `research/launch-baseline.md` documents.
5. Add the read-only observation: periodically (or on a hotkey — your call, whichever is less
   invasive) log `clientSelectionCount` and the non-null entries of `clientSelectionGroup`,
   plus the active player id. Then **actually play a little single-player**: select one unit,
   select several, box-select a group, and confirm the logged values track what is on screen.
6. Write `research/runtime-selection-observations.md` reporting what you observed: do the
   statically-derived addresses hold at runtime? Does the count match? Did the module load at
   the expected base? **Any disagreement between static and runtime is the single most valuable
   thing you can report — do not smooth it over.**
7. Document the whole thing in `tools/plugin/README.md`: toolchain, build command, install and
   uninstall steps, and the injection design decision with its rationale.

## ADDED 2026-08-07 — windowed mode is now a prerequisite, by user decision

The user was offered "one short fullscreen session now" vs "fix windowed mode first" and chose
**fix windowed first**. So getting a windowed game is now part of this task, before step 5.

Your diagnosis stands: `storm.dll` does `LoadLibraryA("ddraw.dll")` then resolves functions by
name, and `WMode.dll` has no export table, so `GetProcAddress` fails and DirectDraw never
initialises. Dropping it into the `ddraw.dll` slot cannot work.

**Hypothesis worth trying first, because it is nearly free for you:** a DLL with no exports and
a `FindWindowA` import is not shaped like a DirectDraw proxy — it is shaped like something
meant to be **injected** into a running process and to locate the game window itself.
`research/launch-baseline.md` noticed that about `WMode_Fix.dll` and did not follow it up. You
already have a working injector. So: try injecting `WMode.dll` (and/or `WMode_Fix.dll`) with
`scinject.exe` instead of proxying it, rather than assuming the ddraw-swap recipe was merely
mis-executed. If that is what those DLLs are for, this costs one run.

If that fails, the fallback is a real chain-loading `ddraw.dll` proxy of your own: export the
entry points `storm.dll` actually resolves, forward each to the genuine 32-bit system
`ddraw.dll` under `SysWOW64`, and hook only what windowed mode requires. Find the required
exports empirically — log what is requested — rather than guessing at the full DirectDraw API.

**Timebox this and report rather than grinding.** If windowed is not converging after a
reasonable effort, say so and we will reconsider; a fullscreen session remains available as a
fallback if the user agrees. Do not let this swallow the runtime verification, which is the
actual deliverable.

Whatever you learn, record it in your research doc — including a plain statement of whether the
merged `launch-baseline.md` recipe is wrong, right-but-misapplied, or unresolved.

## Acceptance criteria

1. A pinned, documented 32-bit C++ toolchain; the build is reproducible from the committed
   docs and scripts, with no hardcoded worktree paths.
2. Our DLL demonstrably loads into StarCraft running from the working copy — evidence in the
   PR (the log line, the launch command).
3. The game remains fully playable with the DLL installed, and windowed mode still works.
   Uninstall verified to restore normal behaviour.
4. Runtime observation of `clientSelectionCount` / `clientSelectionGroup` agrees with what is
   selected on screen across at least three cases (one unit, several units, a box-selected
   group) — or, if it does NOT agree, a precise report of how it differs. Both outcomes pass;
   a vague or assumed answer fails.
5. `research/runtime-selection-observations.md` explicitly states whether the static map holds
   at runtime, including the module base.
6. Pristine install untouched (state how you verified). No game process left running. No game
   content committed. CI green.
7. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/008-plugin-toolchain-inject.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
