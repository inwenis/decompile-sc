# Task 011 — Fan-out: command more than 12 units with one order

## Status

agent: 011
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/11

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task011 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task011-fanout-plugin.
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

- Your inbox: `C:/git/decompile-sc/work/messages/011/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 011 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Make more than 12 units obey a single order.** The user box-selects 36 Marines, right-clicks a
distant point, and all 36 move. That is the whole project's north star and this task delivers it.

Mechanism (chosen from the research, do not redesign it without saying why): keep a plugin-side
selection list of arbitrary size, captured *before* the engine truncates to 12; then when the
player issues an order, emit it as a series of `Select(≤12 units)` + order pairs. The engine's
own cap is never raised — we work within it. This is exactly what BWAPI bots have done on this
binary for a decade, so the mechanism is proven; what is new is driving it from a human's
selection rather than a bot's.

**This is the first task that WRITES to the running game.** Everything before it only observed.

## Build it in stages — each independently provable

Do them in order. Report which stage you reached. **A clean stage B is a better outcome than a
broken stage C** — partial progress that is honestly reported is mergeable and useful.

- **Stage A — prove a hook fires.** Detour exactly one function, log that it was entered, confirm
  the game still runs normally. Nothing else. If this does not work, nothing after it can.
- **Stage B — capture the untruncated selection.** Hook the input path so the plugin records the
  FULL set of units the player selected, before the 12-cap applies. Log it. Still no behaviour
  change — the game should look and play exactly as stock. Prove the list exceeds 12 using the
  test map.
- **Stage C — fan out orders.** When the player issues an order and the plugin list holds more
  than 12, emit chunked `Select`+order pairs so every unit receives it. Restore the visible
  selection afterwards.
- **Stage D — the user verifies in game.** See "How verification works" below.

## Facts you need (all verified by this project, not assumed)

From `research/binary-selection-map.md`, `research/runtime-selection-observations.md` and
`research/selection-cap.md` — read all three:

1. **Module base `0x00400000`, relocation delta zero.** Every static address is usable verbatim.
   Confirmed at runtime. Re-confirm at attach anyway; do not assume.
2. **Sizing constraint that will bite you.** Each `Select` REPLACES `playersSelections[player]`
   rather than adding to it, so N units costs `ceil(N/12)` select+order pairs **plus one** to
   restore the visible selection. A 100-unit intent is roughly 359 bytes, and **each frame's
   command block is length-prefixed by a single byte (255 max)**. So you cannot emit an
   arbitrary number of pairs in one frame — chunk across frames, roughly 4-5 pairs per frame.
   There is also a 512-byte `TurnBuffer` (`0x00654880`) with `sgdwBytesInCmdQueue`
   (`0x00654AA0`). Respect both.
3. **The wire count is UNSIGNED** — resolved from the binary (`JA`, not `JG`). The protocol
   ceiling is 255, not 127.
4. **Two selection arrays exist and they are NOT coherent within a frame.** Measured live: the
   client-side copy updates first and the simulation-side copy caught up 268 ms later, and at
   four units they held the same units in *different order*. Do not assume they agree at any
   instant. `activePlayerSelection` tracks the CLIENT copy, despite sitting adjacent to
   `playersSelections`.
5. **The count byte and the array can disagree.** During teardown, `clientSelectionCount` read 4
   while `clientSelectionGroup` was already all-NULL. Never trust the count alone and walk that
   many slots — validate pointers.
6. **The active player is 1, not 0**, in the observed single-player game. Read the player id;
   do not hardcode an index.
7. Order handlers iterate the receiving player's selection through a shared iterator that is
   gated by a hardcoded compare against 12 (`0x0049A857`). That is *why* fan-out works — each
   chunk is a legal ≤12 selection as far as the engine is concerned.
8. `CUnit` is 336 bytes; selected-unit pointers are unit-array entries.

Input-path and command-path functions are tabulated in `selection-cap.md` §4.1 and §4.3 with
addresses (`SortAllUnits` `0x0046F0F0` and its cap check at `0x0046F208`,
`combineSelectionsLists` `0x0046F290`, `CMDACT_Select` `0x004C0860`, and others). Those addresses
come from public prior art and were confirmed to be real function entry points by our own sweep —
but their *behaviour* is not yet verified by us. Treat them as strong leads, not gospel; if one
does not do what the table claims, that is a finding worth reporting.

## Hard rules

1. **Never modify, write to, or launch `C:\sc-install\Starcraft`.** Work only in
   `C:\sc-work\1161-base`. `tools/plugin/run-with-plugin.ps1` has a canonicalising guard —
   use that script rather than launching by hand.
2. **Offline, single-player only.** Never Battle.net, never multiplayer, never a CD key.
   A modified client must never touch an online service.
3. **Do not patch the game on disk.** All modification is in-memory in the injected plugin.
   `StarCraft.exe` in the working copy must stay byte-identical to pristine — verify and say so.
4. **Provide a way to turn it off** — an environment variable or flag that makes the plugin
   passive. If fan-out misbehaves the user must be able to get a stock game back instantly,
   and "stop injecting" already achieves that, so document it plainly.
5. **Do not try to drive the game with synthetic input.** It was tried and the pointer landed
   hundreds of pixels off target. Final verification is human-driven. Do not burn time here.
6. Never leave a game process running. Reset the working copy between attempts —
   `tools/make-working-copy.ps1 -Force` now PRESERVES the test map and profiles, so this is
   cheap and safe.
7. Commit no game content, no binaries, no logs containing game data.
8. Do not merge your own PR. Do not weaken `scripts/merge-task.ps1`.

## How verification works — read this before planning

**The user performs the final test personally.** A worker cannot reliably click in this game.
When you have something to try, message the conductor with:

1. the exact command to launch it,
2. precisely what the user should do (load which map, select what, click where),
3. what they should SEE if it works, and what a partial success would look like,
4. what to tell you afterwards.

The conductor relays it. Keep the ask under a couple of minutes of their time and assume you get
ONE attempt per round trip, so instrument thoroughly and log enough to diagnose without a second run.

The map is `C:\sc-work\1161-base\Maps\test-many-units.scx` — 36 Marines, single player, no
hostiles. Regenerate with `tools/make-test-map.ps1` if it is missing.

## STAGE D PASSED — finalise the PR (added by conductor 2026-08-07)

**The user ran the test and it worked.** Their report, verbatim, sent 2026-08-07T21:21:40Z:

    run a - 12 moved
    run b - all moved

Map used was `(1)Enslavers02b` (24 units captured), **not** the 36-Marine map — that one was
rejected by the game as corrupt and has since been root-caused and fixed by task 013.

I cross-checked this against your own run-B log before accepting it, and they agree:

    SHADOW captured: 24 units (12 visible + 12 beyond the cap)
    FANOUT start: units=24 (visible 12 + overflow 12) -> 2 Select+order pairs
    FANOUT done: 2/2 chunks emitted, 72 bytes this turn
    STATS mode=fanout fanouts=4 pairs=8 deferred=0 staleSkipped=0

Four orders produced eight pairs, nothing deferred, nothing skipped as stale, 72-74 bytes per
turn against a 200-byte budget. The observe-mode control run on the same map moved 12, so the
result is attributable to the plugin rather than to the map.

**Your only remaining job is to finalise the PR:**

1. Quote the user's result verbatim in the PR body — acceptance criterion 4 requires their own
   account, not your logs.
2. Record that the map was `(1)Enslavers02b` with 24 units, not the original 36-Marine fixture.
3. State the limits plainly so a passing test does not imply more coverage than it has: one map,
   one order-type pair (0x14/0x15), 24 units, single-player, one human run. Orders whose
   semantics depend on the whole selection remain untested.
4. Do not add features. Finalise and report.

**Hard rule 5 is now WRONG and is replaced.** Task 012 proved a script CAN drive this game — not
via `SendInput`, but by posting `WM_LBUTTONDOWN`/`WM_MOUSEMOVE` to the game's own HWND with
client coordinates in `lParam`. Demonstrated live twice, focus not required, and no screen
coordinates are involved anywhere, so the coordinate-failure class is designed out rather than
patched. Replace rule 5 with:

    Do not use SendInput/SendKeys (banned by config/guard-destructive.ps1).
    Posting window messages to the game's own HWND is permitted and works
    -- see research/automated-testing-options.md 4.1.

You do not need to build a driver here. Just stop treating one-attempt-per-round-trip as a
constraint in anything you write.

Do not merge your own PR.

## Acceptance criteria

1. Stage reached is stated plainly and honestly, with evidence for each stage completed.
2. Hooks are installed in memory only; the on-disk `StarCraft.exe` is byte-identical to pristine
   (hash it and show the result).
3. With the plugin passive/disabled, the game behaves exactly as stock — demonstrated, so we know
   the off switch works.
4. If stage C is reached: a user-run test in which **more than 12 units obey one order**, with
   the user's own account of what they saw quoted in the PR. Your own logs alone do not satisfy
   this — the deliverable is observable behaviour in the game.
5. Known limitations stated explicitly: order types not handled, unit counts not tested, anything
   that behaves differently from stock. Orders whose semantics depend on the WHOLE selection
   (archon merge, unload-all) are expected trouble — say what you did about them, even if the
   answer is "not handled".
6. No game process left running; pristine install verified untouched; CI green.
7. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/011-fanout-plugin.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
