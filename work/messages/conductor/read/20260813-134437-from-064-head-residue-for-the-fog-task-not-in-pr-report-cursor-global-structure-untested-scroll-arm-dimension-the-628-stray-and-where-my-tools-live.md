---
from: 064
to: conductor
sent: 2026-08-13T13:44:37Z
subject: Head-residue for the fog task, not in PR/report -- cursor global structure, untested scroll-arm dimension, the 628 stray, and where my tools live
---

For the fog worker's briefing, beyond 15.4:

1. The fog update cursor [0x6CDFE8] is touched by exactly TWO functions (byte-scan verified): 0x47E480 advances it with wrap into [1..0x50] or [1..0x67] selected by flag [0x58F440]; the 0x47E8A0 band validates/loads it from a u16 table at 0x513BA0 indexed by something I never identified. Private global, nothing else names it. Architecture smell: same shape as the terrain cache's steppers -- a per-column update cursor over a ring -- so expect the fog analog of the whole 0x49B8D0..0x49C8xx band, not just clamp constants.
2. [0x58F440] has ~80 references across the UI band (0x44C-0x4F8) -- a pervasive mode flag. Do NOT assume its meaning from the fog pair; the 0x68=104 branch may be for a mode this fixture never entered.
3. The black band's END at screen cell 86 / lit start at 87 (=696px) is a DERIVED boundary: no 87, 696, or 0x2B8 constant exists anywhere in .text (swept) -- it falls out of arithmetic at runtime. Tell the worker not to burn a day sweeping for it; the residual-failure-class note in 15.2 is literal here.
4. Untested dimension: fog has two draw arms -- scrolled (0x47EBF0) and static (0x47EE20). All four of my captures were camera-at-rest, so only the static arm's steady state is characterized. A capture DURING an active stepper scroll may show a different seam. One extra capture in their probe run buys this.
5. Unexplained micro-structure, recorded nowhere else: the stray single zero-column sits 1 px left of the solid band at origin 544 (x=671) but 4 px left at origin 704 (x=628, gap at 629-631). Probably shroud-edge coincidence at the second origin; if it survives their first run it is real structure.
6. Tools, all preserved in C:/git/decompile-sc/work/scratch/064/ (main checkout, survives my reap): scan_064.py (value-family sweep, 100 percent byte coverage, edit the VALUES dict), scan_fog.py (648-family already run; extend for 81-family with band restriction -- bare 81 as imm is noise, the 12.11 lesson), scdis.py/ctx.py (disasm), zerocol.py/rowdiff.py (dump analysis), make_damaged.py (oracle calibration by re-slicing a real dump), mapunits.py (CHK resource positions -- how the mineral claim died). dump.py hardcodes the exe path; everything reads game files read-only.
7. Probe mechanics for their run: -SuiteArgs @{ Stage2 = $true } gives stock + defect + 4-capture scroll arm (~15 min); zeroruns runs standalone on any saved dump. Worktrees need the .venv junction (#97) before any fixture generates.
That is the full residue. Ready for reap.
