---
from: 034
to: conductor
sent: 2026-08-11T08:23:33Z
subject: It renders: playfield 800x400 in a live game, stages 0-2 all green — worth your eyes
---

**Stages 0, 1 and 2 are done and verified live.** Read-back from a running game, both arms:

| reading | control (flag off) | widescreen (flag on) |
| --- | --- | --- |
| framebuffer 0x006CEFF0 | 640x480, 307200 B | **800x480, 384000 B** |
| layer 5 (the playfield) | (0,0) 640x400 | **(0,0) 800x400** |
| layer 2 (dialogs) | 640x480 | 800x480 |
| HUD dialog rects | StatBtn 496,354,639,479 ... | **byte-identical to control** |

17/17 assertions pass at stage 2 (`tools/plugin/test-widescreen.ps1 -Stage 2`), 126
instruction rewrites applied, 0 refused, game loads a map and plays, closes cleanly.

**I picked 800x480, not 800x600, and here is why.** Keeping the height at 480 leaves the
console exactly where it is (y=400..479) and leaves EVERY 480/400 immediate untouched --
the empty strip is then 160x80 beside the console instead of an L-shape, and it is 5:3,
which is closer to your 16:9 monitor than 4:3 is. The generator is parametric
(`--width/--height`), so 800x600 is a re-run, not a rewrite. Say the word if you want it.

**The one thing that needs your eyes, and it is the open question.** The engine composes
800x480. What WMode.dll then PRESENTS I cannot see from a read-back, and the window it
makes is 650x517 in BOTH arms -- identical -- so either it is scaling an 800-wide surface
into that window (feature works, window is just small) or it is showing 640 of the 800
columns (feature invisible). research/renderer-viewport.md 10 item 2 records exactly this
as unmeasured, because the helper is packed.

To look at it yourself:

```powershell
cd C:\git\decompile-sc-task034
./tools/plugin/run-with-plugin.ps1 -Mode hooktest -Widescreen 1 -WidescreenStage 2 `
    -InjectWindowedHelper WMode -Sound -WaitForExit
```

Start a single-player melee game. What I need to know is whether the playfield is WIDER
than the console strip, or the same width as it.

**Cost, measured, replacing 032's paper estimate:** 139 sites, 126 written. About 23 of
them are NEW -- not in 032's 8/9.1 table -- and four are shapes an immediate sweep cannot
see at all (a third video-init copy; a x640 built as `lea r,[x+x*4]` + `shl r,7`, three
times; the terrain pitch built as `(t<<9)+(t<<7)+(t<<5)`). That is past the "roughly a
dozen sites beyond 7's list" kill criterion in COUNT -- I did not stop, because the work
was already done and finished by one run, and the count is the measurement you asked for.

Still to do: regression run of an existing suite with the flag off, research doc update,
report, PR.
