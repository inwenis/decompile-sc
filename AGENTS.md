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
