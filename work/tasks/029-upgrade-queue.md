# Task 029 — Queue upgrades and research at a tech building

## Status

agent: 029
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/34
merged: 2026-08-10

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task029 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task029-upgrade-queue.
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

- Your inbox: `C:/git/decompile-sc/work/messages/029/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 029 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Queue upgrades and research, instead of being able to start only one at a time.** User asked
for this alongside the >5 unit queue and building groups: "enable queuing upgrades". In vanilla,
an Academy / Engineering Bay / Forge runs ONE upgrade and its card goes inert until that finishes.
After this, you can line several up and they run in order.

## Context

- **DESIGN FIRST. Do not build before you have mapped this and told me the plan.** Send me the
  design as a message before implementing. This is the one instruction in this file that
  overrides the usual "just get it green" bar, because the subsystem next door
  (`sc_prodqueue`) spends the player's money and this one will too.
- **Task 025's production queue is the prior art and it is three days old** — read
  `research/production-queue.md` and `tools/plugin/src/sc_prodqueue.cpp` FIRST. Its shape may
  transfer wholesale, or may not: unit training and upgrade research are different engine paths,
  and you must establish which by reading the code rather than by analogy.
- **The lesson 025 paid for, and the reason this task says design-first** (now AGENTS.md, "A
  player-input feature is unproven until the wire has been watched"): 025's original design
  handled a command the client NEVER SENDS — the client greys its own button out and refuses.
  Every offline test passed and the feature was inert. So before you design anything: press an
  upgrade button in a real game with an upgrade already running, and watch the engine's command
  funnel (`queueCommand` 0x00485BD0). What you find there decides the design.
  - If the client refuses to send, the answer is probably 025's inversion — keep the engine's
    slot free so the button stays live, and hold the rest yourself.
  - If it does send and the engine drops it, a receive-side approach becomes possible.
  - Say which it is, with the log.
- **Map it with evidence:** where a building stores its in-progress upgrade, the upgrade/research
  command opcodes (`research/command-opcodes.md`), where the "one at a time" is enforced, and how
  the card's enabled/greyed state is computed (task 026 mapped exactly this — `research/command-card.md`,
  `sc_card.cpp`, and the `techAvailable`/`techResearched` PTEx arrays at 0x0058CE24 / 0x0058CF44,
  player-major). The card work means you can READ the button state rather than infer it.
- **Money, again.** Upgrades cost minerals and gas and have per-level costs. Same hazard as 025:
  nothing may be paid for twice, a cancel must refund correctly, and the UI must not disagree
  with what the building will actually do. 025 solved this structurally by letting every item
  enter through the ENGINE's own accept path so the plugin never spends — prefer that shape if
  it transfers. Task 028 is proving 025's cancel-refund in-game right now; watch what it learns.
- **Scope, deliberately narrow:** upgrades/research queued AT ONE BUILDING. Not cross-building,
  not auto-repeat, not "queue the next level automatically" unless that falls out for free. If
  the level-N/level-N+1 case is messy, queueing the same upgrade twice may simply be refused —
  that is an acceptable answer if you say so.
- **Concurrency:** task 028 is live in `sc_prodqueue.cpp` / `test-production-queue.ps1` /
  `drive-game.ps1`. Prefer NEW files (`sc_upgrades.cpp/h`) and append to `sc_addresses.h` at the
  end. You share the machine and the launch lock with 028 — wait, never kill. If you must touch
  a function 028 also touches, rebase and tell me rather than guessing a merge.
- Test discipline: own `Maps\BroodWar\00-t029\`, `Select-ScBrowserMap`, `New-ScFixtureRun`,
  `run-ci-local.ps1` (`ruff` NOT RUN is fine). GitHub Actions is billing-blocked; ignore it.
  The harness no longer raises the game window — run `watch-foreground.ps1` alongside and report it.
  `make_test_map.py` can set researched tech and starting resources (task 026 fixed its PTEx
  index order — player-major; use the shared `ptex_index()`).

## Acceptance criteria

1. The wire watched FIRST, on a real building with an upgrade already running, and the finding
   stated: does the client send a second research command or refuse. Log included.
2. The subsystem mapped with evidence: storage, opcode(s), every site enforcing one-at-a-time,
   and how the card's greyed state is decided. Addresses carry how-found + how-verified.
3. The design sent to the conductor as a message BEFORE implementation, saying which of the two
   shapes above it takes and why, and how it avoids paying twice.
4. In-game, unattended: queue more than one upgrade at one building, read the queue back from
   MEMORY (not the UI), and confirm they complete in order and take effect (the researched flag
   flips for each, in sequence).
5. Resource safety: each queued upgrade paid exactly once, asserted from the resource globals;
   a cancel refunds correctly or is explicitly refused, with evidence either way.
6. Off by default behind its own flag, like `-ProdQueue`, since it moves the player's resources.
   Tell me the flag name so the deployed launcher can turn it on.
7. No regressions: existing in-game suites + hooktest green; `StarCraft.exe` byte-identical; no
   stranded processes; fixture removed.
8. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/029-upgrade-queue.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
