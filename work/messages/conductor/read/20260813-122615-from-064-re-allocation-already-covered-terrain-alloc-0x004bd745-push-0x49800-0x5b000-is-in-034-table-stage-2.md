---
from: 064
to: conductor
sent: 2026-08-13T12:26:15Z
subject: re: allocation -- already covered: terrain.alloc 0x004BD745 push 0x49800 -> 0x5B000 is in 034 table, stage 2
---

1. Allocation: safe. 034's table already declares `terrain.alloc` -- the `push 0x49800` at 0x004BD745 inside FUN_004BD6F0 (the SMemAlloc into 0x00628454) -- patched to TERRAIN_SIZE = 832*448 = 0x5B000 at stage 2. Patch lands at inject time (plugin refuses to run if video init already up), the alloc runs at console init after that, so the surface is born at the wide size. My 54 sites are all OFFSET/EXTENT arithmetic against that same surface; no writer can pass 0x5B000 with the mod chains fixed, because every chain reduces mod the (patched) size before use. Also verified just now: the four run-writers' wrap tests (patched by 034) and my chain rewrites agree on the same modulus.
2. Margin convention: adopted for PR -- scratch pitch = playfield width + one 32px tile (832=800+32, stock 672=640+32); scratch rows fixed at 448 = 400+48 (height unchanged at this geometry, which is also why every 0xE=14-row constant stays).
3. Enumeration claim, weakened per your note, and this wording goes in the PR: linear resume-past-errors sweep touched 100.0% of .text BYTES; padding/jump-table bytes decode as junk instructions, so coverage means 'no byte unexamined', not 'every decoded instruction is real'. False positives filtered by hand-reading each hit's function (1 discarded: a jne whose TARGET spelled 0x498000). The residual failure class: a constant computed at runtime or split across instructions -- exactly the class the 12.4/12.8 shapes came from, which is why the sweep hunts value FAMILIES (negative encodings, multiples, tile units) rather than the one literal.
4. Since last message: +2 sites, total 56. 0x0048CB80 branch 1 names grid row 18 absolutely (mov edi,0x6cf2c8 at 0x0048CBC7) and holds the same 40*(row-17) count shape 034 patched at 0x004B2303 -- the 21st named grid ref, found by scan, lost between scan and table. At stage 2 those dirty marks go to the DEAD old grid -> missed console-band redraws. Byte-pattern scan confirms exactly two copies of the shape exist; named-ref accounting now closes 21/21.
5. PR framing adopted: enumeration gap wearing a structural costume; 034's bisect was correct about what it could observe.
Building now; probe gets a stage-2 arm with dual captures. Waiting on your GO for the machine.
