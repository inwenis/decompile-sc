# How the status pane draws TEXT — and what it costs to put a number of your own in it

Task 033. Everything here was read out of `StarCraft.exe` 1.16.1 (the working copy at
`C:\sc-work\1161-base`, SHA-256 `AD6B…6A46`, verified before analysis) with this repo's own
Ghidra pipeline, plus one raw dump of `.rdata` taken independently of Ghidra. Every address
carries how it was found and how it was checked (AGENTS.md hard rule 4). Nothing below is
inherited from public prior art — GPTP, teippi and BWAPI all name the *control types*, but none
of them documents the draw path, and the two facts this task turns on (the string comes from
`control+0x14`, and the draw is REFUSED when the box is shorter than the font) are derived here.

Companion documents: [`hud-selection-row.md`](hud-selection-row.md) (the statdata dialog, its
controls and its per-frame pipeline — this document answers its §10 open question 1),
[`production-queue.md`](production-queue.md) §7.1 and §8 (the strip that could not show the
overflow, which is what made this question worth asking),
[`renderer-viewport.md`](renderer-viewport.md) (graphic layer 2, the dialog layer).

---

## 1. The short version

1. **A control draws text because of its TYPE.** The `.bin` relocator assigns every loaded
   control an interact and an update handler out of two default tables indexed by
   `controlType` — `0x005014AC` and `0x00501504`. Types **9, 10 and 11** share one interact
   (`0x00419190`) and have three different updates (`0x004EF9E0` / `0x004EF9C0` / `0x004EF9A0`)
   that differ in **one byte**: the justification. That is a left/centre/right static-text
   triple, read off the tables rather than off a public enum. [§2](#2-the-two-tables)
2. **The string is `control+0x14` (`pszText`), and nothing else.** The update handler's first
   instruction is `MOV EAX,[ECX+0x14]`, and its second is a null test that returns without
   drawing. So a control draws whatever a plain `char*` in that field points at — including
   memory a plugin owns. [§3](#3-the-draw-path-instruction-by-instruction)
3. **The draw is reached from the dialog layer, once per frame, with the DIALOG's surface as
   the render target.** Layer 2's callback `0x0041CB50` walks the dialog list and calls
   `0x0041C080` per dialog, which sets `0x006CF4A8` to `dialog+0x36` and then
   `CALL dword ptr [ECX+0x2E]` — the control's own update handler. [§4](#4-where-it-is-called-from)
4. **A box shorter than the font draws NOTHING, silently.** `0x004202B0` clips against the
   control's own bounds and requires `top + fontHeight <= bottom`; when it fails there is no
   error, no partial glyph and no log — the pane simply looks the way it did before. **This is
   not a hypothetical**: sc_hudrow's page indicator has been spliced, filled and asserted-green
   since task 017 with a nine-pixel-tall box. [§5](#5-the-rule-a-box-has-to-satisfy)
5. **Cost of putting your own number there: one control record and no art.** Allocate a
   `BinDlg`, set type 9, point `pszText` at your own buffer, take the interact/update from the
   same default tables, splice it into the dialog's child list. The engine then draws it in the
   pane's own font and colours, because it *is* the pane's own code doing the drawing.
   [§6](#6-what-a-plugin-has-to-do)

---

## 2. The two tables

`hud-selection-row.md` §3 established that the `.bin` relocator `0x004194E0` fills every loaded
control's `fxnInteract` (`+0x2A`) and `fxnUpdate` (`+0x2E`) from two tables indexed by
`controlType` (`+0x22`):

| table | address |
|---|---|
| default interact | `0x005014AC` |
| default update | `0x00501504` |

Dumped straight out of `.rdata` by `work/scratch/033/peek.py` — a throwaway reader that parses
the PE section table out of the same file it reads, so every VA→offset conversion is derived
rather than assumed:

| type | interact | update | |
|---|---|---|---|
| 8 | `0x00416980` | `0x004EFA00` | |
| **9** | `0x00419190` | **`0x004EF9E0`** | **LSTATIC** |
| **10** | `0x00419190` | `0x004EF9C0` | same interact, different draw |
| **11** | `0x00419190` | `0x004EF9A0` | same again |
| 12 | `0x0041BAA0` | `0x0041B950` | |

**Three types sharing one interact and having three different updates is the shape of an
alignment triple**, and §3 shows the three updates are byte-identical except for the
justification constant they store. BWAPI's `BW/Dialog.h` calls type 9 `cLSTATIC`; that name is
inherited, the *behaviour* is derived here. The plugin does not trust either: it reads both
table entries at runtime and refuses to splice if either is null.

## 3. The draw path, instruction by instruction

`0x004EF9E0`, the whole function (`work/scratch/033/listing-statictext.tsv`; the bytes were
undefined to auto-analysis because nothing but a data table reaches them, so they were recovered
with `DisassembleAt.java` from the table entry itself):

```
004EF9E0  8B 41 14              MOV EAX,[ECX+0x14]        ; pszText -- ECX is the control
004EF9E3  85 C0                 TEST EAX,EAX
004EF9E5  74 12                 JZ 0x004ef9f9             ; no string -> draw NOTHING
004EF9E7  6A 00  6A 00  33 C0   PUSH 0; PUSH 0; XOR EAX,EAX
004EF9ED  C6 05 10 E1 6C 00 11  MOV byte [0x006CE110],0x11 ; justification: 9->0x11
004EF9F4  E8 77 FE FF FF        CALL 0x004EF870
004EF9F9  C2 08 00              RET 0x8
```

`0x004EF9C0` and `0x004EF9A0` are the same nine instructions with `0x12` and `0x14` in that one
store. So `0x006CE110` is the justification/style byte and `0x004EF870` is the draw.

`0x004EF870` (`work/scratch/033/listing-textblit.tsv`), in the order it does things:

1. **Font, from the control's own flags.** `EAX = control->flags & 0x4C00`, then one of four
   handles:

   | `flags & 0x4C00` | handle |
   |---|---|
   | `0x0400` | `[0x006CE0F4]` ← what `CTRL_FONT_SMALLEST` selects |
   | `0x0800` | `[0x006CE0FC]` |
   | `0x4000` | `[0x006CE100]` |
   | else | `[0x006CE0F8]` |

   and `CALL 0x0041FB30` with it in `ECX`. The same function is called again at the tail with
   `ECX = 0`, which restores the previous font — so a control cannot leak its font to the next
   one.
2. **Colour**, `CALL 0x0041F610` with a small style index in `EAX`: `5` when the control is
   disabled (`flags & 0x02`), `4`/`6`/`3` for the static types depending on flag bits, `2`
   otherwise.
3. **The string**: `MOV EAX,[ESI+0x14]`, then `INC EAX` when `flags & 0x0300` — the
   shortcut-prefix byte is skipped rather than drawn.
4. **Position and clip, both from the control's own bounds.** `0x006CE0C8` ← `[ESI+0x04]`
   (left,top as one dword) and `0x006CE0CC` ← `[ESI+0x08]` (right,bottom): the clip box. The pen
   goes to `(bounds.left, bounds.top)` plus the two stack arguments, which the update handler
   passed as `0, 0`.
5. `CALL 0x004202B0` — the blit (§5), which runs the glyph loop `0x004200D0`.

## 4. Where it is called from

Graphic layer 2 is the dialog layer ([`renderer-viewport.md`](renderer-viewport.md): layer 2's
draw slot holds `0x0041CB50`, installed by `0x0041A030`, 640×480). `0x0041CB50` walks the global
dialog list `0x006D5E34`, skipping dialogs without `flags & 8`, and calls **`0x0041C080`** per
dialog per dirty rect. That function ends:

```
0041C08F  MOV EDI,[EBP+0x8]           ; the control
0041C092  CMP word ptr [EDI+0x22],0x0 ; a child?
0041C09C  MOV EDI,[EDI+0x32]          ;   then EDI = its parent DIALOG
...
0041C1D9  ADD EDI,0x36                ; the dialog's surface descriptor
0041C1DF  MOV [0x006CF4A8],EDI        ; ... becomes the current render target
0041C1E5  FF 51 2E   CALL dword ptr [ECX+0x2E]   ; ... and the control draws itself
0041C1ED  MOV [0x006CF4A8],EAX        ; target restored
```

Three things follow, and the module depends on all three:

1. the handler is `__thiscall`-shaped — `ECX` = the control — which is exactly what
   `MOV EAX,[ECX+0x14]` in §3 expects;
2. a control's text lands in **its dialog's own 8-bit surface**, not the screen buffer, so it
   persists until something repaints that rect — which is why removing an indicator means
   asking the engine to update the control underneath it;
3. the surface descriptor is `{u16 w, u16 h, u8* bits}` at **`dialog+0x36`**. (The allocator
   `0x004C35F0` — `SMemAlloc(h * w, "Starcraft\SWAR\lang\status.cpp", 0xB5)` — decompiles to
   the same triple at `+0x0C`, an 0x2A discrepancy that is a register the decompiler could not
   resolve rather than a second surface. The plugin's ink probe tries the evidenced offset
   first, the other as a fallback, and logs which it used; nothing but a diagnostic depends on
   the answer.)

`0x0041C400` (`updateControl`, which the status act calls for every control it shows) is **not**
the draw: it intersects the control's rect with its parent's and marks that region dirty. The
draw happens in the layer-2 pass above. So "show it and call updateControl" is the whole of what
a plugin has to do; the engine draws it on its own schedule.

## 5. The rule a box has to satisfy

`0x004202B0`, decompiled (`work/scratch/033/decomp/drawString.FUN_004202b0.c`), clamps the clip
box to the render target and then draws **only if**:

```c
if (clip.left <= x && clip.top <= y && x <= clip.right &&
    (int)(fontHeight /*0x006CE111*/ + y) <= (int)clip.bottom) { ...glyph loop... }
```

with `x, y` = the control's own top-left and `clip` = the control's own bounds (§3 step 4). So:

> **A static-text control whose box is shorter than the font's height draws nothing at all.**
> Not a clipped glyph — nothing. There is no error path, no return code the caller checks, and
> no log line.

**This has already cost this project a shipped feature.** `sc_hudrow`'s page indicator
(task 017, `research/hud-selection-row.md` §7c) gives its control a box of
`top = button.top + 1`, `bottom = button.top + 10` — nine pixels — and the module then writes
`"36 units  13-24  (2/3)"` into it every page flip. `test-hud-row.ps1` asserted that string **out
of the module's own buffer**, so the feature was green and invisible for weeks, and the user
asked the conductor how to page through the row on 2026-08-11 — a question they would not have
had to ask if a `(2/3)` were on screen. Task 033 raises the box and replaces the self-echo with a
read-back through the control's `pszText` plus an ink count of the dialog surface.

The general form of that mistake is already an AGENTS.md rule ("assert the ENGINE's own result,
not your bookkeeping", task 029). This is the same rule meeting a *drawing* claim: reading a
control's fields proves what it HOLDS, and only the surface proves anything was DRAWN.

### 5.1 The other direction, which is worse, and which ink does NOT catch

A box that is too **short** draws nothing, and a surface ink count catches that immediately. A box
that is too **narrow** draws the string TRUNCATED — and every field read passes, *and the ink
count passes too*, because a clipped string is still ink.

Task 033 shipped that bug into its own first live group run: with four Command Centers selected
the indicator drew `"4 bldgs  4 queued"` into a box **22 pixels wide**, because the box was
clamped to the 34-pixel wireframe button it was anchored to. `mode=2 linked=1 visible=1
text="4 bldgs  4 queued" ink=352` — five correct readings describing a display the player could
not read.

So the box is sized from the STRING, not from the control it hangs off:

```c
int want = strlen(text) * SC_QIND_CHAR_W;   // a deliberate OVER-estimate of the advance
```

over-reserving costs a little slack (the group line's box is only a clip rectangle; the `+N`
badge's box is filled, so it is two frame columns wider than the reservation and no more) and
under-reserving costs the tail of the sentence. Where the box may then extend past the control it started on, the
clean-up path has to repaint everything it covered rather than just the anchor.

**The transferable form:** an oracle that proves a thing HAPPENED is not an oracle that proves it
happened *completely*. `ink > 0` answers "did the engine draw"; only comparing the box against
what it has to hold answers "could all of it fit".

### 5.2 And `ink > 0` does NOT answer "did the engine draw" in this pane either (task 048)

The sentence above overstates what an ink count is worth here, and the correction is worth having
in the same section rather than a task report. **Ink can only detect our text over a region the
engine leaves as background. This pane is not such a region: it draws its own art into the same
8-bit surface the probe counts, so every rect inside it is already saturated before a plugin does
anything at all.**

Two measurements, both live, both from builds that were drawing nothing of the kind:

| where | reading | the box |
|---|---|---|
| `sc_queueind`, task 039 | `refInk=1330`, `ink=448` | 1330 of 1330 bytes over a queue icon, 448 of 448 inside the indicator's own box |
| `sc_hudrow`, task 048 | `indInk=2368` | (32,9,180,25) = 148 × 16 = **2368**, the entire box |

The second one carries the check that needs no source code and no arithmetic: that same `2368`
came back for `"36 units  1-12  (1/3)"`, for `"36 units  13-24  (2/3)"` and for the wrap back to
page 1, **in one run**. An instrument whose reading does not move when its input moves is not
measuring its input — and note the failure looks *healthy*, so the positive control that guards
against `ink = 0` being a blind probe never fires.

What answers the question in this pane is a **difference against the same rect without the text**,
taken on the game thread while the control is not showing (`ScQueueIndBoxDiff`, `indBoxDiff`), and
for the reverse question — "is any of it still there after we stop drawing" — the count of our own
bytes that survive, printed beside the size of what it was looking for (`glyphBytes` / `stranded`).
Keep `ink` on the line; it is corroboration and it is free. Do not assert on it.

## 6. What a plugin has to do

`tools/plugin/src/sc_queueind.cpp`, and it is nine fields:

```c
*(DWORD*)(ind + SC_BINDLG_OFF_FLAGS)    = SC_CTRL_FONT_SMALLEST;   // 0x400 -> the small font
*(short*)(ind + SC_BINDLG_OFF_INDEX)    = -31;                     // NEGATIVE: binder-proof
*(WORD*) (ind + SC_BINDLG_OFF_TYPE)     = 9;                       // LSTATIC
*(DWORD*)(ind + SC_BINDLG_OFF_TEXT)     = (DWORD)myBuffer;         // +0x14, the string
*(DWORD*)(ind + SC_BINDLG_OFF_PARENT)   = root;
*(DWORD*)(ind + SC_BINDLG_OFF_INTERACT) = defaultInteractTable[9];
*(DWORD*)(ind + SC_BINDLG_OFF_UPDATE)   = defaultUpdateTable[9];
*(DWORD*)(ind + SC_BINDLG_OFF_NEXT)     = ChildOf(root);           // splice at the head
*(DWORD*)(root + SC_BINDLG_OFF_FIRST_CHILD) = ind;
// bounds: at least SC_QIND_BOX_H tall (§5), inside a control the engine repaints
```

The `+N` badge points `SC_BINDLG_OFF_UPDATE` at the plugin's own `IndUpdate` instead: same
`__fastcall` shape and `RET 8` as the table entries, it paints the badge's box into the render
target (`0x006CF4A8`) and then hands the text to `defaultUpdateTable[10]` (`0x004EF9C0`, which
stores justification `0x12`; the glyph loop reads it at `0x00420127` and on `TEST AL,2` at
`0x00420130` centres the string between the clip box's left and right, `0x006CE0CC`).

Four points that are not obvious and each cost something to learn:

1. **A negative control id is binder-proof.** The CREATE-time binder `0x00418100` rewrites
   `+0x2A` for every control with `index > 0` from the 44-entry table at `0x00504AF0`
   (`hud-selection-row.md` §3). A negative id is skipped, so the control keeps the handlers it
   was given.
2. **Splice at the HEAD of the child list.** The engine's hide-all sweeps then hide it like any
   other child (so it disappears with the pane), and it is not in the way of any walk that finds
   controls by id.
3. **Put the box inside a control the engine repaints.** The text lands in the dialog's
   persistent surface (§4), so when the indicator goes away its pixels are still there until
   something else draws over them. Anchoring inside an engine-owned control makes "ask the engine
   to update that control" the whole clean-up.
4. **Read the type tables at runtime and refuse if either entry is null.** The table dump in §2
   is evidence about *this* binary; a control the engine has no handler for is a control the
   dialog cannot draw, and a plugin should not hand one over on the strength of a header comment.

## 7. Reproducing this

```powershell
# once: import + analyse into a persistent project (~3 min)
./tools/ghidra/sweep.ps1 -Mode Prepare -InputPE C:\sc-work\1161-base\StarCraft.exe `
    -ProjectDir work/scratch/033/ghidra -LogFile work/scratch/033/ghidra/import.log

# the two default handler tables, straight out of .rdata, independent of Ghidra
python work/scratch/033/peek.py C:\sc-work\1161-base\StarCraft.exe dwords 0x005014AC 20
python work/scratch/033/peek.py C:\sc-work\1161-base\StarCraft.exe dwords 0x00501504 20

# the static-text handlers are reachable ONLY through those tables, so auto-analysis leaves
# them undefined -- recover them from the table entries first, then read them as listings
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/033/ghidra -ProgramName StarCraft.exe `
    -Script DisassembleAt.java `
    -ScriptArgs work/scratch/033/recover.tsv, tools/ghidra/specs/prodind-code-recovery.spec
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/033/ghidra -ProgramName StarCraft.exe `
    -Script ListingDump.java -ScriptArgs work/scratch/033/listing-statictext.tsv, 4EF9A0, 4EFA80
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/033/ghidra -ProgramName StarCraft.exe `
    -Script ListingDump.java -ScriptArgs work/scratch/033/listing-textblit.tsv, 4EF870, 4EF9A0
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/033/ghidra -ProgramName StarCraft.exe `
    -Script ListingDump.java -ScriptArgs work/scratch/033/listing-dlgdrawwalk.tsv, 41C080, 41C200

# the decompiles quoted above
foreach ($s in 'textcallees','textinner') {
  ./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/033/ghidra -ProgramName StarCraft.exe `
      -Script DecompileMany.java -ScriptArgs "work/scratch/033/decomp/index-$s.tsv", "tools/ghidra/specs/prodind-$s.spec", 180
}

# the hook target's prologue, and its callers
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/033/ghidra -ProgramName StarCraft.exe `
    -Script HookProbe.java -ScriptArgs work/scratch/033/hookprobe/targets.tsv, tools/ghidra/specs/prodind-hooks.spec
```

The `.asm`, `.c` and listing outputs are whole disassembled/decompiled functions — derived game
content. They stay under `work/scratch/` (gitignored) and only the findings above are committed
(hard rule 1).

## 8. The live layout, read from the running dialog

`hud-selection-row.md` §10 left "the exact bounds of the controls, and of the usable free
margin, live in `rez\statdata.bin`; stage B should read them from the live dialog and log them,
not hardcode" as an open question. `ScQueueIndLogDialog` (`QINDDLG` lines, one per child: id,
type, flags, bounds, update handler, text) does exactly that, and the production strip's own
bounds were read out of a live run before anything was positioned against them:

| control | id | bounds (dialog-relative) |
|---|---|---|
| status dialog | — | `(138,388,407,479)` on screen — 269 × 91 |
| queue icon, display 0 | 2 | `(104,14,142,49)` |
| queue icon, display 1 | 3 | `(104,53,142,88)` |
| queue icon, display 2 | 4 | `(143,53,181,88)` |
| queue icon, display 3 | 5 | `(182,53,220,88)` |
| queue icon, display 4 | 6 | `(221,53,259,88)` |

Which settles where a "+N" goes without inventing a position: **inside control id 6**, the last
icon — and while `-ProdQueue` is holding the ring at `SC_PRODQ_ENGINE_HOLD = 4`, that icon is
precisely the one the engine draws EMPTY. The count goes in the hole the feature itself creates,
and the module computes the box from that control's live bounds every time rather than from the
numbers in this table.
