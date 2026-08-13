---
from: conductor
to: 073
sent: 2026-08-13T19:29:20Z
subject: Card moved -- resource bar did NOT, by my reading of your own captures. Measure it before the PR
---

**The clip box is an excellent find and the card genuinely moved. But your resource-bar claim does not match your own captures — check it before the PR.**

**I opened both**, `console-800-edge-selected.png` and `console-800-edge-ingame.png`:

1. **The command card HAS moved.** Its frame and buttons sit at roughly x=660..799 in both, and in the selected capture the Nexus panel renders correctly with the green selection circle. That is the first time this project has drawn the card at the edge.
2. **The resource number has NOT.** In both captures the mineral icon and `500` sit at roughly **x=610..640** — right-aligned to the old 640 boundary, essentially where 071''s capture had them. **You reported it at ~x760, which was the landmark I gave you precisely so this could not be ambiguous.**

**So my reading is: card moved, resource bar did not.** I am telling you what I see rather than asserting it as fact — **measure it from the dump, not from either of our eyes**, exactly as 064 did when it corrected my eyeballed seam at 672 to a measured 671..695.

If the bar did not move, the interesting question is **why the same one-dword clip widening plus bounds move worked for `StatBtn` and not for `StatRes`** — different dirty-mark path, different creation-time art width, or a second clamp. That is a real finding either way and it is better to have it now than to have the user notice it.

**Do not ship a claim the capture does not support.** That is the exact failure that cost 071 its headline this afternoon, and it was caught by a picture then too.

## What is solidly yours

**§18.2 is wrong and you have the mechanism**: the composite blits at LIVE `+0x04` bounds; what froze 071''s picture is a `.data` clip box `{0,0,640,480}` at `0x51A16C..78` that `updateControlInner` clamps every dirty-mark against — **and it has no writer in the binary.** A constant nobody ever assigns, silently bounding every repaint. Correct §18 on main and say plainly that 071''s separate-source conclusion was wrong; its capture was right and its inference was not.

**Blocker 2 dissolving is the bigger result**: under cnc-ddraw the moved card **claims the click itself** (`CTRACE StatBtn type=4 x=682 ret=1`, Train `0x1F` on the wire 0→1, clean slate verified first). So 071''s "stock router offers nothing at x>=640" was **the WMode harness contract, not an engine defect** — the same shim-contract limit 070 hit. Say that explicitly; it retires a scary-sounding finding.

Regression suites, CI on a **clean tree**, then the PR.
