# Task 002 — Safe working copy + PE anatomy + launch baseline

## Status

agent: 002
model: sonnet
pr: https://github.com/inwenis/decompile-sc/pull/3
merged: 2026-08-06

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task002 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task002-working-copy-baseline.
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

- Your inbox: `C:/git/decompile-sc/work/messages/002/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 002 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Establish the physical foundation every later task builds on: (a) a **safe, reproducible
working copy** of the StarCraft 1.16.1 install that we are free to patch, (b) a documented
**PE anatomy** of `StarCraft.exe` and `storm.dll` in `research/`, and (c) a **launch
baseline** — proof of whether the game runs from the working copy, and the exact command
to launch it (windowed if possible) for fast iteration. Deliverables are docs + scripts;
no binaries are ever committed.

## Context

- **The pristine install lives at `C:\sc-install\Starcraft`. It is READ-ONLY to you,
  absolutely.** Never write, patch, rename, or delete anything there. It is the user's
  clean reference copy and their playable game. Copy OUT of it only.
- Verified fingerprint (conductor, 2026-08-06) — your copy must match these exactly:
  - `StarCraft.exe` 1,220,608 bytes, FileVersion 1.16.1,
    sha256 `AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46`
  - `storm.dll` 409,600 bytes, v1.16.1,
    sha256 `706FF2164CA472F27C44235ED55586644E5C86E68CD69B62D76F5A78778BFF25`
  - `battle.snp` 557,310 bytes, v1.16.1
  - whole install: 242 files, ~1,068 MB (~1,040 MB of that is `.mpq` asset archives)
- **Working copy path: `C:\sc-work\1161-base\`** — OUTSIDE the repo, so nothing game-related
  can ever be committed. Create it. Never put game files inside `C:/git/decompile-sc` or
  your worktree.
- Code surface we care about is only ~2.2 MB: `StarCraft.exe` + `storm.dll` + `battle.snp`.
  The `.mpq` files are art/audio/maps — copy them (the game needs them to run) but do not
  analyse or extract them in this task.
- `WMode.dll` and `WMode_Fix.dll` ship in the install — these are the community windowed-mode
  helpers. Windowed mode is strongly preferred for later automated iteration; find out
  whether it can be enabled without modifying the pristine install.
- The game may depend on registry keys written by the installer (install path, CD key).
  Determining whether the copy launches, and what it needs, is a core output of this task.
- Python 3.11 and a `.venv` exist. `pefile` is the natural tool for PE anatomy — add a
  `requirements.txt` if you introduce deps.
- Ghidra is NOT required here and task 001 is still standing it up — do not wait on it and
  do not install it.

## Safety rules (hard)

1. Never modify `C:\sc-install\Starcraft` in any way.
2. Never commit a game binary, `.mpq`, extracted asset, or memory dump. Check `git status`
   before every commit.
3. If you launch the game: **offline / single-player only**. Never connect to Battle.net or
   any online service, never enter a CD key you were not given, never touch multiplayer.
4. Always terminate any game process you start (bounded wait, then kill). Do not leave a
   fullscreen window running — the user is asleep.
5. If launching turns out to require something you cannot do safely or without the user
   (a CD key, an online activation, a registry write outside the working copy), STOP and
   message the conductor with `-Type question`. Do not improvise around it.

## Steps (suggested)

1. Copy `C:\sc-install\Starcraft` → `C:\sc-work\1161-base` (robocopy or Copy-Item). Verify
   integrity: recompute sha256 for the three key binaries and compare against the values
   above; compare file count and total size. Report any mismatch as a failure.
2. Write a committed, idempotent script `tools/make-working-copy.ps1` that reproduces step 1
   from scratch (source and destination as parameters, defaults as above), verifies hashes,
   and refuses to run if the destination already exists unless `-Force`. This is how any
   future task gets a clean patch target.
3. PE anatomy of `StarCraft.exe` and `storm.dll` → `research/pe-anatomy.md`. Cover: machine
   type / bitness, image base, entry point RVA, section table (name, virtual address, virtual
   size, raw size, characteristics — flag which are executable vs data), imports grouped by
   DLL, exports (for storm.dll), timestamp, subsystem, any signs of packing/obfuscation or an
   unusual/legacy linker. State the evidence for each claim (which field of which header).
4. Write `tools/pe_report.py` that regenerates that report from any PE, so the doc is
   reproducible rather than hand-typed. Wire it into `requirements.txt` if it needs `pefile`.
5. Launch baseline. Attempt to launch `C:\sc-work\1161-base\StarCraft.exe`. Determine and
   document: does it start from the copy? does it need registry keys, and which? can it be
   run windowed via the bundled WMode helpers? Use a bounded wait (e.g. 30s), confirm the
   process exists, capture what you can (process name/pid, window title if obtainable), then
   kill it. Record the exact working launch command — or, if it will not launch, the precise
   blocker and what would unblock it.
6. Write `research/launch-baseline.md`: the launch command, prerequisites discovered,
   windowed-mode status, and a short "how to iterate fast" note for future patch tasks.
7. Add `C:/sc-work/` to `.gitignore` as belt-and-braces (it is outside the repo, but a future
   worker may symlink or copy).

## Acceptance criteria

1. `C:\sc-work\1161-base` exists and its `StarCraft.exe` / `storm.dll` sha256 match the
   values in Context exactly. Pristine install verifiably untouched (state how you verified —
   e.g. hashes + last-write times unchanged).
2. `tools/make-working-copy.ps1` is committed, idempotent, hash-verifying, and was actually
   used or re-run successfully at least once. Evidence in the PR.
3. `research/pe-anatomy.md` documents both binaries with per-claim evidence, and
   `tools/pe_report.py` regenerates it.
4. `research/launch-baseline.md` states plainly whether the game launches from the copy, the
   exact command, and the windowed-mode answer. An honest "it does not launch because X" is
   a PASS; a vague or guessed answer is a FAIL.
5. `git status` clean of binaries: no `.exe`, `.dll`, `.mpq`, `.snp`, asset or dump files
   committed anywhere. No game process left running.
6. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/002-working-copy-baseline.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
