# decompile-sc — rulebook

## What this repo is

Personal, private reverse-engineering research on StarCraft. Primary target:
the 1.16.1-era binary (richest public prior art — BWAPI offsets, community
struct maps, prior decompilation efforts). Deliverables are DOCUMENTATION
and TOOLING, not redistributed game content.

## Project hard rules

1. NEVER commit game binaries, MPQ archives, extracted assets, or anything
   derived from them that reproduces game content. The repo tracks findings
   and tooling only. `.gitignore` blocks the common extensions; the rule
   covers everything the ignore patterns miss.
2. The local game copy lives at `game/` (gitignored) and is READ-ONLY to
   workers. Need to patch a binary? Copy it into your worktree or
   `work/scratch/` first.
3. Never point a modified binary at Battle.net or any online service.
   Offline and single-player only.
4. Every claimed address/offset/struct must carry evidence: how it was found
   and how it was verified. No guessed offsets in `research/`.
5. NEVER write to live user state outside the repo and the working copy —
   registry keys, `%APPDATA%`, Documents, the desktop. The user's machine is
   not a test bench. Specifically: `HKCU:\SOFTWARE\Blizzard Entertainment\*`
   holds their real game settings (2026-08-08 incident: `New-Item -Force` on
   an existing key DELETES AND RECREATES it — 22 settings wiped, restored
   from a lucky pre-existing dump, MRU list partly lost). Prove any
   state-touching mechanism against a throwaway key/path first, and prefer a
   process-scoped mechanism over persistent user state whenever both work.
   Deployment targets the user chose (the deploy dir, a desktop shortcut) are
   the exception — write those, but never destructively (see `tools/deploy.ps1`
   player-data rules).
6. `C:/git/conductor` and `C:/git/conductor-task*` are ANOTHER LIVE SYSTEM
   (a separate orchestrator with ~25 in-flight agents and real user
   messages). NEVER read, modify, `cd` into, or run git/gh against them from
   this repo — touching them is a data-loss incident. Everything this repo
   needs from there is already ported into `scripts/`/`config/`; if
   something seems missing, ask the user. (Sole exception: `./run.ps1`,
   which the USER launches to serve the Agent Console UI.)

## Read a dialog's content from memory, not from its pixels (2026-08-09, task 026)

A frame-region hash is NOT a reliable oracle for what a dialog shows. Task 023 concluded a
researched fixture "drew a different command card" from two differing region fingerprints;
task 026's read of the card's own slot table showed both fixtures identical — the hash was a
false positive. When a claim is about UI CONTENT (which button, which slot, enabled vs greyed),
read the structure out of process memory (the control array, the statUser records, the button's
state bits), not a screenshot of it. Frames are corroboration for "did it visibly render at
all", never the measurement. Same lesson the folder-row "flake" taught: what looks visual is
usually a readable structure underneath.

## A player-input feature is unproven until the wire has been watched (2026-08-09, task 025)

If a feature begins with a player input — a click, a hotkey, a button on the command card —
an offline proof of your logic can be confidently, completely wrong. The client may never
send the command you are handling.

Task 025 built over-cap production queueing against a receive-side handler, and every
offline test passed. In game the queue never grew: pressing Train twelve times put exactly
FIVE commands on the wire and then nothing, because the client greys its own button out and
refuses to send a sixth. The handler was waiting for a command that does not exist. The
whole design had to be inverted (keep the engine's ring below its cap so the button stays
lit) — and only a real run showed it.

So: for anything that starts with player input, watch the engine's command funnel
(`queueCommand` 0x00485BD0) in a real game BEFORE trusting your handler. Offline tests
prove your code does what you meant; only the wire proves the game asks it to.

## Absence assertions must first be proved positive (2026-08-09)

An assertion that something is ABSENT is worth nothing until the same pattern has been shown to
MATCH somewhere it should. Two suites gated "the stock arm installed no hooks" on a string the
plugin never logs (`HOOK install`, when the real lines are `HOOK <name>: installed at ...` and
`HOOK: n/n installed`). The check could not fail, and a research doc cited it as the reason the
control was trustworthy.

So: prove the pattern positive against a log where the thing DID happen, then require it absent
where it should not have. Pair every absence check with a positive one — "the ability fired in
this arm" alongside "nothing was interrupted" — or a silently broken run reads as a clean result.

## Never click a map-browser row by number (hard rule, 2026-08-09, task 023)

**`Select-ScBrowserMap` walks the browser. Nothing else does.** It scrolls the list to a
known top, computes every row from the filesystem, and makes the browser prove the row it
clicked was a map. A hardcoded `-X 117 -Y 140` is the defect that cost six runs in one day,
and it has three levels — the fixture folder's row, the map's row inside it, and the row of
`[Up One Level]`, which sorts ALPHABETICALLY AMONG THE FOLDERS and therefore moves when any
task creates a fixture folder. That third one broke a suite that generates no fixture and
shares no folder, so "I don't use the shared folder" is not an exemption.

The list also opens ALREADY SCROLLED, which is why a computed row is not enough on its own
and why the sync comes first. Details and evidence: the block comment above
`Get-ScBrowserListing` in `tools/plugin/drive-game.ps1`.

## Test fixtures: one folder per task, one NAME per suite (hard rule, 2026-08-09)

**Generate into `Maps\BroodWar\00-t<NNN>\`, your own folder — never the shared
`00-testmap`.** This removes the contention in both directions instead of racing for it.
Suites take `-FixtureDir` for exactly this: more than one task runs some of them, so the
folder is the caller's choice, not the suite's.

**Name the fixture after the SUITE, not the task** (`burrow-fanout.scx`). Two suites
generating `lurkers.scx` made "delete only your own file" undecidable between them and
blocked a run outright.

**Declare every fixture a run will create, up front** (`New-ScFixtureRun`). Ownership is
per-run, not per-file: the old one-filename rule counted a suite's own earlier fixture as
foreign and made it wait for itself. Declaring is not softening — anything outside the
declared set is still foreign, and refusing is still the answer.

Remove the folder at the end of the run, and only if it is empty — an empty folder of yours
still pushes every entry below it down a row for everyone else, and only six rows are
visible at once.

The rules below still apply INSIDE your own folder (they are what caught the incidents):

## Shared test-fixture folder (hard rule, 2026-08-09 incident)

Every in-game suite generates its map into ONE shared folder in the working copy, and the
map browser is clicked **by ROW, not by name** — so a file another worker drops in there
changes which map YOUR test loads. On 2026-08-09 task 021's run played task 022's fixture
(36 Ghosts where it places Lurkers) and then recursive-deleted the folder.

Rules, all three, no exceptions:

1. **Name every generated fixture for its suite** (`burrow-fanout.scx`) and declare it to
   `New-ScFixtureRun`, so "mine" is decidable from the filename alone.
2. **Delete only your own declared files**, on every path including `finally`. Never
   `Remove-Item -Recurse` that folder.
3. **Refuse to start if any `.scx` you did not declare is present** — whether or not a game
   is running. Process-liveness is NOT a sufficient test: the other worker's run may begin
   seconds after yours generates its fixture.
4. **Re-check immediately before the browser walk**, not only at generate time. The
   folder can be cleared or added to in between — task 022 lost a run to exactly that. Throw
   with the cause named rather than playing whatever is there.

Rule 3 is what prevents the silent failure — playing someone else's map produces internally
consistent nonsense, which is worse than a crash.

## Foreground: only ONE primitive may raise (hard rule, 2026-08-09, task 027 — reverses 022/023)

**The rule has two halves and you need both. Reading one half alone re-opens a real bug.**

1. **Posted mouse MOVES, clicks and world DRAG-boxes do NOT need the foreground.** Nothing
   in the harness may raise the window for them. This is the half that reverses 022/023.
2. **A DROPDOWN pick DOES** — `Send-ScDropdownPick` is the one and only place in this repo
   allowed to raise, it does so for the length of one pick, and it hands the foreground
   back afterwards. Delete that and the Game Type pick silently stops taking. Details at
   the end of this section.

Half 1 used to be stated the other way round. It was wrong, and the wrong version cost the
user their focus on every unattended run — the complaint that opened task 027.

Two kinds of evidence:

- **Static.** The window procedure (`StarCraft.exe` `FUN_004d1d70`, Ghidra) handles
  `WM_MOUSEMOVE` with three unconditional stores and a return — no foreground check, no
  active check: `DAT_006cddc0 |= 1; _DAT_006cddc4 = lParam & 0xffff; _DAT_006cddc8 =
  lParam >> 16;`. The binary's only `GetForegroundWindow` call site (`0x004eddf0`) is a
  diagnostic.
- **Live** (`tools/plugin/probe-quiet-input.ps1`, one launch). With the USER'S window
  holding the foreground throughout, a posted move onto the main menu's Single Player
  button changed that button's region (`FF975A03A546737B` → `271D215ABFB1EF45`). Then
  raising the game put it straight BACK to `FF975A03A546737B`: activation re-syncs the
  game's cursor to the physical mouse, so the raise **destroys** the posted position it
  was supposed to enable.

Activation is worse than useless here. The same `WM_ACTIVATEAPP` case (`case 0x1c`) runs
`0x004d1750` and `0x00421730`, which call `SetCursor`/`GetCursorPos`/`SetCursorPos` and
**`ClipCursor(window rect)`** — every raise confined the user's real mouse to the game
window.

What 022 actually measured was a DRAWING difference, with a frame oracle: the game gates
drawing on activation (`0x0041d710` returns 0 while `DAT_0051bfa8`, written by that same
`WM_ACTIVATEAPP` case, is 0). Under the windowed-mode helper every suite injects, drawing
does NOT stop — the probe fingerprinted the animated main menu 3 s apart with the window in
the background and got two different frames — so the pixel oracles (browser rows,
`Set-ScGameType`) work in the background too.

So:

- `Assert-ScWindowActive` no longer touches the foreground. It refuses to post into a dead
  or **MINIMISED** window, which is the real hazard (task 012 probe 2), and that is all.
- `Set-ScWindowActive` still exists, opt-in only: `-RaiseWindow`, or `$env:SCDRIVE_RAISE=1`
  for a human who wants to watch a run. **No suite may set it.**
- Do not "fix" a flaky input by activating the window. It will not be the cause, and it
  will steal the user's focus and trap their mouse while the run lasts.

### Half 2: the dropdown, the one place a raise is allowed

**Measured, not assumed: `Send-ScDropdownPick`.** A menu dropdown is a press-and-hold
control and the game calls `SetCapture` on button-down (`0x004d1a76`); Windows grants the
mouse capture only to the FOREGROUND window. `probe-quiet-dropdown.ps1` ran all three arms
on the Create Game screen: background = pick did not take, background + `AttachThreadInput`
+ `SetActiveWindow` = pick did not take, foreground = took on the first attempt. So that
primitive raises for the length of ONE pick and then **hands the foreground back** to
whatever had it (which also makes the game release its `ClipCursor`). Cost: about two
seconds during the menu walk of the three suites that call `Set-ScGameType`, instead of the
whole run. A world drag-box is also a held-button walk and needs none of this — so this is
the dialog control, not held buttons in general.

### How to check a run did not steal focus

`tools/plugin/watch-foreground.ps1` samples `GetForegroundWindow()` every 250 ms and prints
one line per CHANGE, exiting non-zero if any StarCraft window was ever foreground. Run it
alongside a suite; do not claim "it did not steal focus" without it.

What a correct run looks like: for the six suites that never pick a game type, **zero**
changes — `test-fanout-orders` and `test-selection-circles` (the pair 022/023 cited) both
went 0 failures with the user's window keeping the foreground for the entire run. For the
three that do pick one, exactly one borrow-and-return pair around the pick (measured:
foreground at 22:03:39, back to the user's window at 22:03:43). Anything else is a bug.

## The in-game tips dialog is dismissed by ITS OWN button, never by a fixed point (task 027)

`Tips_Dlg` is a normal engine dialog, and every suite used to close it with an
unconditional click at `(200,261)` — no check that it was there, no check that it went.
Use `Dismiss-ScTipsDialog -Hwnd -LogPath`: it waits for the dialog in the engine's own
active-dialog list (the plugin's `DIALOGS` log line, list head `0x006D5E34`), computes the
OK button's centre from that button's own bounds, clicks it, and **throws if the dialog is
still up**. A tip dialog left open eats every later click in the run.

Never turn tips off through `HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft` — that is
live user state (hard rule 5) and the dialog's own "Show Tips at Startup" checkbox writes
it. Dismiss for this run; leave the user's setting alone.

## Screenshots vs hard rule 1 (settled)

The global rule "visual change → screenshot → `pr-image`" does NOT apply to game frames.
`pr-image` pushes to a branch in this repo, and a game frame reproduces game artwork,
which hard rule 1 forbids. Hard rule 1 wins — always, without asking.

Instead: prove visual claims with the in-process read-back oracles (`CIRCLES show:`,
`HUDROW show n=… page=…`, `UNITSTATE`), describe the appearance in the PR body, and keep
frames on the gitignored diagnostic path for the conductor or user to open locally.
Workers have correctly declined the screenshot twice (tasks 016, 021); this section exists
so nobody has to weigh it a third time.

## Layout

- `work/` — orchestration DATA.
  - `work/tasks/` — task files (`_template.md`, `NNN-<slug>.md`).
  - `work/reports/` — task reports (`NNN-<slug>.md`).
  - `work/messages/<agent-id>/{inbox,read}/` — agent messaging. NEVER delete
    or overwrite anything under `work/messages/` (2026-07-17 data-loss class).
  - `work/scratch/` — logs, agent registry, throwaway (not committed).
- `scripts/` — spawn + messaging tooling (ported from the conductor repo).
  `config/` — worker settings + guard hooks.
- `research/` — per-subsystem findings (units, sprites, AI, netcode, …).
  The product of this repo. Evidence rule (hard rule 4) applies to every file.
- `tools/` — Python analysis scripts + Ghidra headless automation.
- `game/` — gitignored local install copy. Read-only (hard rule 2).

## Roles

- Spawned with a prompt naming a task file → you are a **worker**. The task
  file is your full contract — it starts with ZERO chat history. Follow it
  plus this rulebook.
- Otherwise → you are the **conductor**. The conductor DISPATCHES: cuts
  tasks, spawns workers, monitors, reviews, integrates. It does not write
  product code, tooling, or research itself — diagnosis it already holds
  goes INTO the task file, not into an editor. (Exception: maintaining this
  repo's own orchestration data and docs.)

## Task lifecycle

Status is DERIVED, never written. No `state:` line exists; nothing a worker
or conductor writes says "running" or "done". Precedence — the
furthest-along observable wins:

| status    | glyph | derived from                                          |
| --------- | ----- | ----------------------------------------------------- |
| completed | ✓     | `merged:` stamp in the task file (close-task.ps1 stamps it) |
| review    | ◎     | the task's PR is open                                 |
| blocked   | ⏸     | a worker question with no `re:` answer                |
| running   | ●     | a `work/scratch/agents/NNN.json` registry entry exists |
| queued    | ○     | none of the above — nobody has started                |

Workers write exactly three things, none a status: the `pr:` link, a report,
and questions. An unanswered question IS the blocked signal; answering it
clears it. Never hand-write `merged:` — close-task.ps1 stamps it.

Flow: cut → spawn → monitor (derived status + conductor inbox) → review
(MANDATORY GATE: no unreviewed change merges; check acceptance criteria
yourself, do not trust the worker's word) → merge → close.

### Never stop an agent without checking for an in-flight game (2026-08-09 incident)

`stop-agent.ps1` kills the agent's process tree. It does NOT kill a
StarCraft the agent launched — the game outlives its driver, keeps the
launch lock, and blocks EVERY other worker until someone notices.

This happened: task 024 messaged "ready for merge", started one last
regression run six seconds later, and the conductor stopped it mid-run.
The orphaned game held the machine for ~18 minutes while two workers
queued behind it, one of them prepared to wait 90.

Before `stop-agent.ps1`, ALWAYS:

1. `Get-Process StarCraft` — if one is running, do not stop the agent yet.
2. "Ready for merge" does NOT mean "idle". A worker may start verification
   runs after reporting. Ask it to confirm it is idle, or merge first and
   stop it when it acknowledges.
3. After stopping, re-check for a surviving game and for a
   `C:\sc-work\logs\sc-launch.lock` naming a dead pid.

Killing an orphan is allowed ONLY with positive proof it is orphaned — a
dead parent, a test output file that has stopped growing, and a lock file
naming a dead pid. Otherwise the standing rule holds: another worker's
game is another worker's run, and workers must never kill one themselves
(ask the conductor).

## Spawning workers

All commands run from `C:/git/decompile-sc` via the PowerShell tool (see
§ Messaging for why never Bash).

```powershell
# Cut a task + worktree + spawn in one command:
./scripts/new-task.ps1 -Slug <slug> [-Model sonnet] [-Title '...'] [-NoSpawn] [-Commit]
#   allocates next free NNN, fills work/tasks/_template.md into
#   work/tasks/NNN-<slug>.md (Goal/Context left as TODO(conductor) — fill them),
#   git fetch + worktree add C:/git/decompile-sc-taskNNN off origin/main.

# Spawn separately (after -NoSpawn):
./scripts/spawn-agent.ps1 -TaskFile work/tasks/NNN-<slug>.md -WorkDir C:/git/decompile-sc-taskNNN -Model <model>

# Merge — the ONE merge command, never `gh pr merge` by hand:
./scripts/merge-task.ps1 -Task NNN
#   refuses unless: caller is conductor, task has pr: and no merged:,
#   PR open, not behind origin/main, checks green. Squash-merges, then closes.

# Close a hand-merged PR (merge-task.ps1 calls this itself):
./scripts/close-task.ps1 -Task NNN [-StopAgent] [-Prune]
#   verifies PR is MERGED via gh (refuses otherwise), stamps merged:, commits
#   the task file + report. -Prune removes the clean worktree + branch.
```

- Conductor pre-creates the worktree and spawns the worker inside it
  (`-WorkDir`) — zero permission prompts. Default permissions: bypass.
- One task per worker. Parallel work → separate task files, one tab each.
- A finished no-PR task (research, `pr: -`) has nothing to merge — commit its
  task file + report directly after review.

## Messaging

Messages are files: `work/messages/<agent-id>/inbox/` (waiting) and
`read/` (processed). agent-id = task number for a worker (`003`),
`conductor`, or `user`. One message = one file with `from / to / sent /
subject` front matter.

- **PowerShell-not-Bash foot-gun**: run every `.ps1` via the PowerShell
  tool, NEVER the Bash tool. Bash invokes Windows PowerShell 5.1;
  `#Requires -Version 7` fails SILENTLY — nothing is written and the call
  looks sent. Always verify the script printed the written file path.
- NEVER delete or overwrite anything under `work/messages/` — real user
  messages live there. Reading files anywhere: fine.

```powershell
# Send:
./scripts/send-message.ps1 -To <agent-id> -From <agent-id> -Subject <s> (-Body <text> | -BodyFile <path>)

# Read + file in ONE atomic act (never cat + move later):
./scripts/read-message.ps1 -Agent <agent-id> [-All]

# Ask the human a decision — console renders one button per option:
./scripts/send-message.ps1 -To user -From NNN `
  -Subject 'Which Ghidra version?' -Body 'optional markdown context' `
  -Type question -Options '11.2; 10.4; no preference'
```

- `-Subject` IS the question; `-Options` is semicolon-separated, two or more.
- The answer arrives as a normal inbox message carrying `re: <question file>`.
  That `re:` line is what derives blocked/answered — the question file itself
  is never rewritten.
- Workers: arm a Monitor on your inbox at startup, send READY, re-arm after
  each message. A from-USER file in a worker inbox is informational — the
  conductor reviews and relays; workers act only on from-CONDUCTOR messages.
- Conductor: watch `work/messages/conductor/inbox/` while any worker runs;
  keep `work/messages/conductor/status.json` honest
  (`{"state","subject","updatedAt"}`).

## Model assignment

| model  | use for                                                        |
| ------ | -------------------------------------------------------------- |
| haiku  | trivial/mechanical: renames, file moves, format fixes          |
| sonnet | standard: well-specified tasks, investigations with clear steps |
| opus   | complex: multi-step judgement, gnarly debugging                |
| fable  | hardest: highest-ambiguity investigation, architecture         |

Record the choice in the task file (`model:` in Status).

## Conventions

- Worker worktrees: `C:/git/decompile-sc-taskNNN`, branch `taskNNN-<slug>`.
- Task ids: 3 digits, never reused, gaps never refilled. Slugs:
  lowercase-kebab (letters, digits, hyphens).
- Task heading: `# Task NNN — <title>` with an EM DASH (—, U+2014), spaces
  around it. Hard parser gate — a hyphen there makes the task INVISIBLE to
  the UI and to refresh-pr-status.ps1.
- Status block fields: `agent:`, `model:`, `pr:` only. No `state:` (status
  is derived), no hand-written `merged:` (close-task.ps1 stamps it).
- Reports: `work/reports/NNN-<slug>.md` unless the task reports via PR.
- PowerShell 7 only (`#Requires -Version 7` on every script); scripts run
  via the PowerShell tool, never Bash.
- Global rules in `~/.codex/AGENTS.md` apply to workers automatically.
