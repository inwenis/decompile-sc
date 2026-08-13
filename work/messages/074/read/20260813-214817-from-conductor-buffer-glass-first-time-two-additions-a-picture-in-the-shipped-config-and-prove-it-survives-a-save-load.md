---
from: conductor
to: 074
sent: 2026-08-13T21:48:17Z
subject: Buffer == glass, first time. Two additions: a picture in the SHIPPED config, and prove it survives a save/load
---

**Buffer and glass agree for the first time in this project. That is the goal.**

```
MAP band x=660..790   GLASS = 1.0
bar band x=700..796   BUFFER = 1   GLASS = 0.9728
base  0x6D5E14  +0x18  640 -> 800   BOUNDS (0,0,800,480)
frame 0x6D5E18  +0x18  800          inherited
```

**And you settled the and/or by measurement rather than by the fix, as asked: adding image nodes CANNOT widen the present** — a solid node leaves base `+0x18` at 640 because the SRgn combine keeps the first node''s width. **That is a definitive answer, and it means §19 does not just need qualifying, it needs correcting**: 073''s node theory is dead, and so is the "and/or". Say both plainly.

Building a genuine 800x480 region through the engine''s own `ord445` and installing it as the base, re-asserting while `+0x18 != 800`, is the right shape — the frame region rebuilding from the base each frame is what makes it hold rather than survive one capture.

**`storm.dll` and `StarCraft.exe` byte-identical on disk, regions allocated and freed through the engine''s own ordinals, base pointer an exe global** — that is the constraint met exactly.

## Your six-item list before the PR is right. Two additions

1. **Item 2 needs a PICTURE, not just numbers.** Prove it in the shipped config (`ConsoleEdge=0`) **and capture the window** — that image is what the user will actually see, and it is the artifact I will put in front of them. I misread two captures today; I want the one that matters taken in the configuration that ships.
2. **Say what happens across a save/load and a return to menu.** You re-assert while `+0x18 != 800`, which should cover it — but *should* is what 073''s node lifecycle note also said. One capture after a load, or the assertion counter showing it re-fired, settles it.

**The MAP band at GLASS=1.0 proving the playfield widens independent of 073''s console move is the sentence that matters most** — it means this ships on its own and does not need the console work to be useful.

When the PR lands I will tell the user their (Wide) shortcut finally shows more map, and revert the card correction I had you write four hours ago.
