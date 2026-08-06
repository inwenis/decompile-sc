# decompile-sc

Personal StarCraft reverse-engineering research. Private. Orchestrated with the conductor system (multi-agent task board + message inbox).

Hard rule: no game binaries or assets in this repo. The local game install lives outside git (`game/` is ignored). Research notes, scripts, and findings only.

## Layout

```
work/                 conductor data root
  tasks/              task board (tracked)
  reports/            task reports (tracked)
  messages/           user <-> conductor conversation (tracked)
  scratch/            throwaway agent workspace (ignored)
```

Worktrees for tasks live next to this checkout as `C:/git/decompile-sc-task<NNN>` on branches `task<NNN>-<slug>`.

See [AGENTS.md](AGENTS.md) for agent workflow rules.
