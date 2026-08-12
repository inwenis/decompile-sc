---
from: conductor
to: user
sent: 2026-08-12T22:29:54Z
subject: conductor issue #2 filed. Your skills repo already HAS architecture-delta-review -- but the local clone is 25 commits stale and deploys to the wrong directory
type: question
options: Pull and deploy the skills repo now; Pull only, do not touch my home directory; Leave it, I will do it myself
---

Three answers, and the middle one is better news than I expected.

## 1. Conductor cannot schedule tasks — issue filed

**https://github.com/inwenis/conductor/issues/2**

It can cut a task, spawn a worker, merge and close. It has no way to say "run this every month" or "run this every N merged tasks". The only scheduling anywhere near it is the harness's own `CronCreate`, which is session-only — memory, never on disk, gone when the session ends, auto-expiring after 7 days regardless. That is what drives my board sweep tonight and it is useless for anything longer than a shift.

I checked that properly rather than by search, because **my first check was blind and I nearly filed on it**: GitHub code search returns 0 for `cron` in that repo — and also 0 for `agent`, `task` and `spawn`, in an agent orchestrator. It simply is not indexing the repo. The real evidence is the file tree: 283 paths, and the only one matching `cron|sched|recur|timer|periodic` is `src/ui/pulse/playgroundBeatSchedule.ts`, a UI animation helper.

The issue argues for "every N merged tasks" over a calendar, since risk here accumulates per change rather than per week — and notes that if conductor grows scheduling, it should ask before creating OS-level scheduled state on someone's machine rather than doing it during onboarding.

## 2. Your skills repo already has the skill I was about to design

**`architecture-delta-review/SKILL.md`** — it exists, and it is close to exactly what I proposed to you an hour ago, written better. Its own framing:

> Given what this system now does, would we still design the modules, classes, abstractions, and data flow this way today?

Read-only by construction (*"Do not edit files. Do not implement fixes. Do not refactor."*), explicitly triggered **after** a change lands rather than on a clock, and its verdict scale is the useful one — from "no refactor needed" through "a small preparatory refactor" to "actively harmful, but changing it needs an explicit human decision".

That is the recurring job. I will point the delta reviews at it rather than writing my own brief.

Also in there and relevant to tonight: **`verify-first/SKILL.md`**.

## 3. Your local clone of it is 25 commits stale — and the newest commit is the one that matters

    C:/git/skills   local  865ef0b   2026-06-22
                    origin 1e58b56   25 commits ahead
                    working tree clean, nothing of yours at risk

The head commit on origin is literally **`Merge pull request #5 from inwenis/fix-deploy-link-claude-skills-dir`**.

Your stale `deploy.sh` symlinks skills into `~/.config/agents/skills/` — that is **Amp's** skills directory, not Claude Code's. That path does not exist on this machine, so those skills have never been visible here. Only `conductor` and `conductor-onboard` are installed under `~/.claude/skills/`, and they came from the conductor repo's own installer.

So: pull, run deploy, and `architecture-delta-review` becomes available to me directly.

**I have not pulled and have not deployed.** The pull is trivially safe — your tree is clean and it is a fast-forward — but deploying writes symlinks into your home directory, and after the 08 Aug registry incident I do not create state outside this repo on my own initiative. Say the word and I will do both, or just the pull.

## 4. "Is our code concise/solid?"

That is inside task 052's brief already — it is ranked by whether something can make us believe a false thing or break something you can see, which is the honest version of "solid". Once the skills repo is current, the recurring follow-ups should run through `architecture-delta-review` instead of my hand-written brief, so we are using your own tooling rather than a one-off.
