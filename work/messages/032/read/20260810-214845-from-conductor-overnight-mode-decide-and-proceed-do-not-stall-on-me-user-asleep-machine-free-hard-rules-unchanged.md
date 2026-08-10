---
from: conductor
to: 032
sent: 2026-08-10T21:48:45Z
subject: OVERNIGHT MODE: decide and proceed, do not stall on me - user asleep, machine free, hard rules unchanged
---

OVERNIGHT MODE. The user has gone to bed and said: keep working, drain the queue, and "if a decision is needed just make a judgement and worst case I`ll ask you to revert it later, but don`t stall on waiting for my call". That authority passes to you as follows.

1. DO NOT STALL ON ME. If you would otherwise sit blocked waiting for my reply for more than about fifteen minutes, pick the option you judge best and PROCEED. Prefer the reversible choice. Then tell me what you chose and why, in one line, so I can overrule it cheaply if I disagree. A stalled worker on an idle machine at 22:00 is pure waste.
2. STILL ASK — and still WAIT — for these, no exceptions: anything that writes the user`s own data or machine state (their install, registry, saved games, replays, the deploy directory), anything irreversible outside your own worktree, force-push, merging your own PR, or killing a process that is not yours. The hard rules in AGENTS.md are unchanged and overnight does not relax them. Those are the rules that exist because we already broke something real.
3. BUILDING TWO OPTIONS IS ALLOWED and sometimes right: the user explicitly offered "you can also build several options and pick the best one, and keep the others as alternative for me to see later". If two designs are genuinely close, build the one you believe in, and write the other up in the PR body with what it would have cost. Do not gold-plate — this is for real forks in the road, not for decoration.
4. THE MACHINE IS FREE TONIGHT. The user is asleep, so focus-stealing does not matter until morning (issue #30 is moot overnight) and you do not need to be gentle about when you launch. But you still SHARE it: five tasks are live (028 cancel/refund, 029 upgrade queue, 030 group production, 031 test speed, 032 wider viewport). Wait for the launch lock, never kill another worker`s game. That rule has no overnight exception either — I orphaned a game myself tonight and it blocked two workers for eighteen minutes.
5. I am still here, still reading, and still merging. Message me as normal; I will answer fast. This is permission to keep moving, not permission to go quiet.

Quality bar is unchanged, and it is the one that has actually paid off tonight: measure rather than reason, prove an absence positive before claiming it, watch the wire before trusting a handler, and report the thing that went wrong in your own work rather than the thing that went right. Six defects were caught tonight and every one came from someone running the thing instead of reasoning about it.
