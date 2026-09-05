# decompile-sc

Personal StarCraft reverse-engineering research. Private.

Hard rule: no game binaries or assets in this repo. The local game install lives outside git (`game/` is ignored). Research notes, scripts, and findings only.

## Layout

```
research/   per-subsystem findings -- the product of this repo
tools/      plugin, Ghidra automation, map + deploy tooling
tests/      Pester tests for the tooling
work/       scratch/ (ignored build output + logs), defects/ (patches for build-defect-arm.ps1)
```

See [AGENTS.md](AGENTS.md) for the rulebook.
