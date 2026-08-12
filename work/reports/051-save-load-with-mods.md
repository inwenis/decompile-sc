# Task 051 — Does saving and loading a game work with the plugin active

Sections 1–4 were written BEFORE any game was launched; sections 5–7 are written only
from real runs. All six arms ran.

---

## 1. The answer

**Works, with one real caveat and one real bug.** Saving and loading a game with the
plugin active preserves everything the ENGINE owns — the production ring, the units,
their hp and positions, the resources — in every arm, including a save taken while the
plugin was holding three items above the engine's five. The caveat is that those
over-cap items are **not in the save file** and cannot be: they live in the plugin, so
loading that save in a plugin-free game silently drops them (paid for, never delivered).
The bug is worse and is the thing to fix: **the plugin's held items survive a load and
follow you into a different game** — load an older save after queueing over the cap and
the plugin is still holding items from the game you left, attached to whatever building
now occupies that memory.

For the user, in their terms: *saving and loading works. Don't count on a queue longer
than five surviving into a game you load without the mod, and after loading an older
save you may see units you never queued — that one is a bug and has an issue open.*

---

## 2. The user's real saves are untouched (acceptance criterion 4)

Hashed at the very start of this task, BEFORE any other work, with
`Get-FileHash -Algorithm SHA256` over every file under
`C:\sc-deploy\starcraft-modded\game\save\` and `…\characters\`.

| file (relative to `…\starcraft-modded\game\`) | bytes | mtime (UTC) | SHA-256 before |
| --- | --- | --- | --- |
| `save\asdf\aaa.snx` | 207052 | 2026-08-11T22:41:45Z | `77496461D0F60C8CA8BE8FD71525B6E574385108FABB05691D000D6C57A243C0` |
| `save\asdf\task018.snx` | 230707 | 2026-08-08T15:42:19Z | `3F6763A3CB5C4023D8076B89620189E5618F64ECFFAAF67411F652D446020319` |
| `characters\asdf.spc` | 36 | 2026-08-07T20:50:48Z | `3F5700D1E1812390A8D8A722045E1A363A2754EEFEB7502A0B23A6367E40726C` |
| `characters\deploy-only-marker.spc` | 55 | 2026-08-08T14:13:37Z | `4EE9EC54A10991A2AAF7F4202CFA52CCFAF770C907250E1A664BB129F1CFA323` |

**After-hashes, taken when every arm had run — all four files byte-identical:**

| file | SHA-256 after | same as before? |
| --- | --- | --- |
| `save\asdf\aaa.snx` | `77496461D0F60C8CA8BE8FD71525B6E574385108FABB05691D000D6C57A243C0` | yes |
| `save\asdf\task018.snx` | `3F6763A3CB5C4023D8076B89620189E5618F64ECFFAAF67411F652D446020319` | yes |
| `characters\asdf.spc` | `3F5700D1E1812390A8D8A722045E1A363A2754EEFEB7502A0B23A6367E40726C` | yes |
| `characters\deploy-only-marker.spc` | `4EE9EC54A10991A2AAF7F4202CFA52CCFAF770C907250E1A664BB129F1CFA323` | yes |

Modification times are unchanged too, and the file COUNT is unchanged (4 → 4), so nothing
was added or removed either. `VERDICT: all 4 files byte-identical`.

The suite does write saves — six of them — but every one is under
`C:\sc-work\1161-base\save\asdf\` (`slctl.snx`, `slfour.snx`, `slcap.snx`), the throwaway
working copy. It also temporarily moves the working copy's OTHER saves aside so the load
dialog can only list the one file an arm means, and puts them back in a `finally`; a
recovery step at the start of every run restores anything a killed run left behind. The
deploy directory is never opened.

Every experiment in this task runs against `C:\sc-work\1161-base\`, a separate
working copy with its own `save\asdf\` and `characters\asdf.spc`. Nothing in this
task reads-modifies-writes, deletes or overwrites anything under the deploy dir.

---

## 3. What the ENGINE does on save, read from its own instructions

Static, before any run, on `C:\sc-work\1161-base\StarCraft.exe` (SHA-256
`AD6B58B2…C6A46`, pristine 1.16.1), with `pefile` + `capstone`
(`work/scratch/051/find_save_strings.py`, `…/disasm051.py`).

**Correction to the task brief.** The string `** Single Player Save Format ver %d.%d`
is **not present in this binary** — a full printable-string sweep of `.text`,
`.rdata`, `.data` and `.rsrc` for `save` returns eight hits and that is not one of
them. What IS there, and what the brief was right about, are the original source
filenames the asserts carry:

| VA | string | referenced from |
| --- | --- | --- |
| `0x00502700` | `Starcraft\SWAR\lang\saveload.cpp` | 10 sites, `0x004C2D70`, `0x004D00E9`…`0x004D0739` |
| `0x005046CC` | `Starcraft\SWAR\lang\sai_LoadSave.cpp` | 5 sites, `0x0046EAE9`…`0x0046EB72` |
| `0x005047AC` | `Starcraft\SWAR\lang\CUnitSave.cpp` | 2 sites, `0x004EAB9F`, `0x004EAC24` |
| `0x00501680` | `rez\savegame.bin` | 7 sites — the save dialog's own UI resource |
| `0x0050284C` | `save\` | `0x004CE576`, `0x004CE669`, `0x004CE67F` |
| `0x00502834` | `*.snx` | `0x004A70D0`, `0x004CE4B8`, … — the save-file enumerator |

**The unit serialiser, at `0x004EAB8F`–`0x004EAC2B`** (the function that carries the
two `CUnitSave.cpp` asserts, lines 160 and 183):

```
0x004EAB8F  imul  eax, eax, 0x154      ; count * (4 + 0x150)
0x004EAB9E  push  0x5047ac             ; "CUnitSave.cpp", line 0xA0 -> SMemAlloc
0x004EABD2  mov   cl,  [ebp+eax-0x6b4] ; per-unit "save this one" flag
0x004EABE0  mov   [edx], eax           ; the unit INDEX, 4 bytes
0x004EABEA  mov   ecx, 0x54            ; 0x54 dwords = 0x150 bytes = one whole CUnit
0x004EABEF  rep movsd                  ; ...copied VERBATIM
0x004EABF1  add   edx, 0x150
0x004EABFD  add   esi, 0x150           ; stride = sizeof(CUnit)
0x004EABCB  mov   dword [ebp-8], 0x6a4 ; 1700 units — the whole table
```

So a save writes **`index` + the entire 336-byte `CUnit`, byte for byte, for every
live unit**. `CUnit+0x98` — the five-slot production ring — and the ring head are
inside that copy, so **the engine's own five queued items are serialised and restored
by construction.** The unit table walked is the static one at `0x0059CCA8`
(`0x0059CD0C - 0x64`, stride `0x150`, 1700 entries), which is the same array
BWAPI names `UnitNodeTable`.

**What this immediately tells us about the plugin.** The plugin's over-cap items do
not live in any `CUnit`. They live in the plugin's own `g_rec[]` table
(`tools/plugin/src/sc_prodqueue.cpp`), keyed by the `CUnit*` address. **Nothing in the
save file can carry them**, and nothing in the load path can restore them. That makes
two concrete, testable predictions, and the in-game arms below exist to decide between
them:

1. **Loss** — items the plugin was holding above the engine's five are gone after a
   load, and the minerals/gas the engine already took for them are gone with them.
2. **Phantom promotion** — worse, and not exclusive with (1): `g_rec[]` survives the
   load in the same process, still keyed by addresses in a *static* unit table that the
   load has just refilled. A record whose address now holds a *different* building
   would make the plugin promote items into a building that never queued them.

---

## 4. The comparison set, and the arms — written down BEFORE running anything

### 4.1 What "works" means here

A round trip works if the state the ENGINE holds after the load equals the state it
held at the save, over this set. Every field is read out of the engine's own memory by
the plugin's **read-only** scans (`-WorldScan 1`, `-CardScan 1`), which install no hook
and write nothing — that is what makes the same oracle usable in the no-plugin control
arm and in the fanout arms (`scplugin.cpp` `ScanWorld`, `sc_card.cpp` `STATQ`).

| # | field | where it is read | oracle |
| --- | --- | --- | --- |
| A1 | ring head index (`CUnit + BUILD_QUEUE_SLOT`) | the producing building's own memory | `STATQ … head=` |
| A2 | the five ring slots at `CUnit+0x98`, in ring order | same | `STATQ … engine=[…]` |
| A3 | `engineLen` — occupied slots, derived from A2 | same | derived |
| A4 | status-pane portrait type + owner | the status dialog | `STATQ … ptype= powner=` |
| B1 | unit count per player | the engine's per-player unit lists | `WORLD … p=N units=` |
| B2 | multiset of (type, owner) over all units | same | `WORLD` per-unit lines |
| B3 | hp and map position of the fixture's static units | same | `WORLD` per-unit lines |
| C | plugin overflow count + types (fanout arms only) | the plugin's own table | `PRODQSEL … overflow=` |
| D | minerals + gas (fanout arms only) | the engine's resource globals | `PRODQSEL … minerals= gas=` |

**A1–A3 are the verdict.** C is NOT a verdict — it is the plugin's own bookkeeping
(AGENTS.md § "Assert the ENGINE'S OWN RESULT"), reported only to localise a failure to
the save side or the load side. D is fanout-only because the resource globals are
printed on the `PRODQSEL` line and that line does not exist without `-ProdQueue 1`;
where D is unavailable the arm says so rather than implying resources were checked.

A4 is there because of task 039: a reading about "the queue" taken while the pane holds
a different unit is a reading about the wrong building.

### 4.2 The seam, and the coverage line every arm must print

The seam this task exists to reach is **a save taken while the plugin is holding items
above the engine's five**. An arm whose overflow was 0 at save time cannot detect the
over-cap failure class whatever its verdict says, so every arm prints

```
COVERAGE  overflow held at save time = N   (N=0 => this arm CANNOT see the over-cap class)
```

next to its verdict (AGENTS.md § task 041).

### 4.3 The arms

| # | plugin on SAVE | plugin on LOAD | logical queue at save | what it decides | verdict |
| --- | --- | --- | --- | --- | --- |
| 1 | none (observe, no hooks) | none (observe) | 4 (all in the ring) | positive control: does vanilla round-trip a queue at all | NOT RUN |
| 2 | fanout (deployed flags) | fanout | 4 (ring only, no overflow) | fanout with nothing above the cap | NOT RUN |
| 3 | fanout | fanout | 8 (4 ring + 4 held) | **the seam** — over-cap save/load | NOT RUN |
| 4 | fanout | none (observe) | 8 (4 ring + 4 held) | user saves modded, plays vanilla later | NOT RUN |
| 5 | none (observe) | fanout | 4 (ring only) | user saves vanilla, plays modded later | NOT RUN |
| 6 | fanout | fanout | 8 held at building A, then load a save of a DIFFERENT game | phantom promotion into a recycled `CUnit` slot | NOT RUN |

Arm 1 comes first: an "it is broken under the plugin" result means nothing until the
same measurement has been shown to come out clean without it
(AGENTS.md § "Absence assertions must first be proved positive").

"none (observe)" = the plugin attached in `-Mode observe`, which installs **no hooks**
and writes nothing to game memory. It is present only to answer the marker with the
same read-only oracle the other arms use. The absence of hooks is asserted positively:
the fanout arms' logs must contain `HOOK <name>: installed at …` lines and the observe
arms' logs must contain none.

### 4.4 Fidelity to what the user actually runs

The fanout arms launch with the flags `tools/deploy.ps1` bakes into the user's own
shortcut — `-Mode fanout -Circles 1 -HudRow 1 -ProdQueue 1 -ProdFan 1 -UpgradeQueue 1
-QueueIndicator 1` — plus `-WorldScan 1 -CardScan 1`, which only add read-only scans.

### 4.5 Drift, and how a measurement window is kept honest

Game time passes between the S1 read and the write of the file, and again between the
load finishing and the S2 read. Only a *completing* item changes ring contents, so the
fixture uses a build time long enough that no item can complete inside either window,
and every arm re-reads `promoted`/`engineLen` to prove none did. An arm in which an item
completed inside a window is reported INCONCLUSIVE and re-run — never averaged away.

---

## 5. The save/load dialogs, mapped for the first time

Nothing in this repo had ever driven these dialogs, so before the arms could run, a probe
(`tools/plugin/probe-save-load-dialogs.ps1`, `-Mode observe`, stock campaign map, no
`Set-ScGameType` call and therefore no dropdown) dumped the engine's own dialog list at
every step. Everything below is read out of the engine, not assumed.

### 5.1 The in-game menu is `GameMenu`, and its hotkeys are inside the strings

```
dlg 'GameMenu' rect=184,32,447,319
  ctrl '.Return to Game (.Esc.)' rect=20,252,243,279 type=1 flags=0x20001A18
  ctrl 's.S.ave Game'            rect=20,36,243,63   type=2 flags=0x20000A18
  ctrl 'l.L.oad Game'            rect=20,70,243,97   type=2 flags=0x20000A18
  ctrl 'p.P.ause Game'           rect=20,70,243,97   type=2 flags=0x20000A10
  ctrl 'r.R.esume Game'          rect=20,70,243,97   type=2 flags=0x20000A10
  ctrl 'o.O.ptions' / 'h.H.elp' / 'jMission Ob.j.ectives' / 'e.E.nd Mission'
  ctrl 'Game Menu'               rect=0,8,263,31     type=10 flags=0x808
```

F10 opens it, one press, and the plugin's dialog walk sees it. Pause and Resume share one
rect and are complementary, the same shape as the card's Cancel/Lift-Off pair (task 039).

### 5.2 The save dialog is `SaveGame`, and its name box is readable

```
dlg 'SaveGame' rect=128,32,511,287
  ctrl 'ssss'      rect=32,44,351,61   type=8  flags=0xC0001098   <- the name EDIT box
  ctrl 's.S.ave'   rect=20,216,123,243 type=1  flags=0x20080A18   <- the default button
  ctrl 'd.D.elete' rect=140,216,243,243 type=2 flags=0x20000A18
  ctrl 'c.C.ancel' rect=260,216,363,243 type=2 flags=0x20000A18
  ctrl 'Save Game' rect=0,8,383,31     type=10 flags=0x4008       <- the title
```

Two things follow, and both were needed before an arm could run:

* the EDIT control (type 8) **does** carry readable text in the engine's walk, and it
  opens **pre-filled with the last save's name** (`ssss` in this working copy) — so a run
  that types without clearing gets a name it did not choose;
* a match of `^(OK|Save)$` can never hit the button, whose letters are `sSave`. The
  suite matches `Save$`, which also separates the button from the title (`SaveGame`).

### 5.3 The typing helper doubled every character — caught by the read-back rule

`Send-ScText` first drove the box through `Send-ScKey -Char`, which posts WM_KEYDOWN,
WM_CHAR and WM_KEYUP. This dialog's edit control honours **both** the key-down and the
char, so:

```
typed 'slprobe'  ->  ctrl 'ssllpprroobbee' rect=32,44,351,61 type=8
```

read out of the engine's own control text. Fixed: the character path now posts WM_CHAR
alone, and the probe **asserts** the box reads exactly what was typed rather than printing
it.

**Scope, stated precisely:** `Send-ScText` is new in this task and has no callers anywhere
in `tools/` on `main`, so this was a bug in a new helper caught before it shipped — not a
latent fault under the existing suites. What is worth keeping is the method: it was found
by asserting the ENGINE'S control text instead of trusting the variable the script typed
from (AGENTS.md § task 033). A suite that trusted its own variable would have saved under
a name it never chose and then looked for the wrong file.

### 5.4 One fixture fact, found the same way

On the stock campaign map under the current game type, the status bar reads `Observing`
and the local player owns nothing. That map can therefore never carry a production-queue
fixture, which is independent confirmation that the arms need the generated UMS map.

---

## 6. Results — the arms

Every arm below ran to a verdict. Each one's LOAD is proved to have happened by a witness
(§ 6.2), and each prints the overflow it held at save time, because an arm with overflow 0
cannot see the class of bug this task exists to find.

| # | plugin on SAVE | plugin on LOAD | queue at save | seam? | verdict |
| --- | --- | --- | --- | --- | --- |
| 1 | none (observe, 0 hooks) | none (observe) | ring 4, held 0 | no | **PASS** — positive control |
| 2 | fanout (deployed flags) | fanout | ring 4, held 0 | no | **PASS** |
| 3 | fanout | fanout | ring 5, **held 3** (logical 8) | **yes** | **PASS** |
| 4 | fanout | none (observe) | ring 5, **held 3** | **yes** | **PASS for engine state; the 3 held items are gone** |
| 5 | none (observe) | fanout | ring 4, held 0 | no | **PASS** |
| 6 | fanout, then load a DIFFERENT save | fanout | n/a | **yes** | **FAIL — the bug** |

Arm 1 ran first and is load-bearing: without it the others would be uninterpretable.

Run totals, so the table and the transcripts agree: `[control] 0 failure(s) across 1 arm`,
`[fanout] 1 failure(s) across 4 arms` — that one failure IS arm 6, the bug — and
`[crossload] 0 failure(s) across 1 arm`.

### 6.1 What each arm actually read

Arm 1 (`test-save-load [control]: 0 failure(s)`):

```
at save : head=0 engineLen=4 engine=[0x040,0x040,0x040,0x040,0x0E4] units(p0)=3
at load : head=0 engineLen=4 engine=[0x040,0x040,0x040,0x040,0x0E4] units(p0)=3
ok  A1 head  ok A2 ring slots  ok A3 count  ok A4 portrait
ok  B1 unit count  ok B2 types  ok B3 completed hp+position
```

Arm 3, **the seam** — a save taken while the plugin held three items above the engine's
five, with a clean measurement window:

```
at save : head=0 engineLen=5 engine=[0x040,0x040,0x040,0x040,0x040] overflow=3 minerals=2600
at load : head=0 engineLen=5 engine=[0x040,0x040,0x040,0x040,0x040] overflow=3 minerals=2600
WINDOW    completed units (player 0) 2 -> 2, plugin promotions 0 -> 0
COVERAGE  overflow held at save time = 3 -- this arm DOES reach the over-cap seam.
```

The engine's ring came back byte-identical and the plugin's three held items were still
held. **In-session, a logical queue of 8 survives a save/load round trip intact.**

Arm 4 — the same save loaded with NO plugin:

```
at save : engineLen=5 engine=[0x040 x5] overflow=3 minerals=2600
at load : engineLen=5 engine=[0x040 x5] overflow=-1  (no plugin, so no overflow at all)
```

The engine's five come back exactly. The three held items are simply absent — they were
never in the file, because the file has nowhere to put them. The player paid 8 × 50 = 400
minerals and will receive five Probes. **150 minerals of units vanish**, silently.

### 6.2 The witness — why any of these verdicts mean anything

Every assertion above passes when the two states MATCH, and **a load that never happened
produces exactly that match**, because the game simply carries on with the state it
already had. The first control run passed all nine assertions with no evidence a load had
occurred at all — on the same run that proved a posted click on the save dialog's own
button does nothing.

So each arm now plants a witness: after the save, it queues one Probe at the SECOND Nexus
— a building the suite never measures, which the save recorded with an empty ring —
asserts that mutation landed, and requires the load to have erased it.

```
ok  witness: the second Nexus now holds 1 queued item the save does NOT contain
ok  witness: THE LOAD REALLY REPLACED THE WORLD (witness ring 1 -> 0)
```

`1 -> 1` is reported as INCONCLUSIVE — not a pass and not a save/load failure.

### 6.3 The bug (arm 6): held items survive a load and follow you into another game

Load the save the **no-plugin** arm wrote — a file containing a queue of four and no
overflow whatsoever — into a fanout process that had earlier queued 8 at the same building
in a **different game**:

```
ok   arm6: the loaded vanilla game's ring holds ONLY what the vanilla save had (4 occupied)
FAIL arm6: the plugin holds NOTHING for a game it never queued in (overflow=3, tracked buildings=1)
PRODQSEL [arm5-load-45] unit=0x00623E58 ... engine=[0x040,0x040,0x040,0x040,0x0E4] overflow=3 logical=7 minerals=2800
```

The engine restored its own array perfectly. The plugin walked into the loaded game still
holding three Probes from the game before it, bound to `0x00623E58` — the address the
restored Nexus now occupies.

Why it resolves at all, and why it cannot be caught by the existing guard:

* the engine restores units **into its static 1700-slot table in place**, so the same
  building is at the same address before and after a load (`unit=0x00623E58` in every arm);
* `RecordStillLive` (sc_prodqueue.cpp) validates a record by uniqueness byte, player and
  hp — and a save restores all three **verbatim**, so a stale record looks alive;
* the ring is at 4 and the hold is 4, so nothing promotes yet. The moment one Probe
  finishes and a slot frees, `PromoteInto` puts a phantom item into a building that never
  queued it, paid for in a game that no longer exists.

Reproduction in the user's terms: **queue more than five at a building, load any earlier
save, keep playing.**

**The obvious test does not catch this.** The first version of arm 6 compared the ring
only, and the ring is the half that is right — it passed. Only asserting on the plugin's
own table in a game it never queued in exposes it.

**What a reproduction REQUIRES — three things, all in ONE process, in this order.** This
matters because the arm that looks superficially similar cannot show it:

1. fanout mode with `-ProdQueue 1`, so the plugin has a `g_rec[]` at all;
2. that process queues OVER the cap in game A, creating a record with `count > 0`
   (arm 3: `overflow=3`);
3. the SAME process then loads a DIFFERENT save whose own file contains no overflow
   (arm 6 loads the file the no-plugin control arm wrote).

`-Phase fanout` alone reproduces it end to end, because arm 3 creates the stale record and
arm 6 loads across it. **The `crossload` phase cannot see this and its clean result is not
evidence against it**: that phase runs `-Mode observe`, so the loading process has no
plugin table to carry anything stale — the plugin says so itself on that arm's line,
`load: (no PRODQSEL line -- this arm has no production queue)`. The leak is a property of
the LOADING process, not of the file.

GitHub issue: [#63](https://github.com/inwenis/decompile-sc/issues/63).

### 6.4 Harness failures vs engine findings

Eight of the failures logged tonight were **my harness, not the game**. Split explicitly,
because a reader must be able to tell which failures are claims about StarCraft:

| symptom | actually was | now |
| --- | --- | --- |
| "the engine wrote no new .snx" | a posted click on the save dialog's own button does nothing | click **and** Return, print which worked |
| "no new .snx" on every re-run | overwrite raises `OkCancel`, unhandled | handled as a state in a loop |
| a successful overwrite read as failure | detector counted NEW files; an overwrite creates none | detector compares last-write time of the named file |
| `0 Train commands reached the wire` | `CMD id=` lines come from the command hook, absent in observe | assert the engine's ring instead; report the wire count |
| `ring holds 4 after 8 clicks (5)` | my expectation was wrong: at the cap the ring is left FULL | expect `min(Queue, 5)` |
| nine green assertions, no load | no witness | witness, § 6.2 |
| arm 3 INCONCLUSIVE | a Probe completed inside the window at 90 s build time | 240 s, still asserted |

The genuine engine/plugin findings are exactly two: the over-cap items are not in the save
file (§ 6.1, arm 4), and the stale-record contamination (§ 6.3).

---

## 7. Engine facts learned, and one rule worth keeping

### 7.1 A posted click does not always fire an engine dialog button — and "type=1" is not the rule

| control | dialog | type | flags | posted click at its own centre |
| --- | --- | --- | --- | --- |
| `o.O.K` | `Tips_Dlg` | 1 | `0x20081A58` | **works** (every run, for a year of suites) |
| `l.L.oad` | `LoadGame` | 1 | `0x20081A18` | **works** (measured this task) |
| `o.O.K` | `OkCancel` | 1 | `0x20001A98` | **works** |
| `s.S.ave` | `SaveGame` | 1 | `0x20080A18` | **does not** |

All four are `type=1` default buttons, so "a posted click never fires a default button" is
false. The only one that fails is the only one **missing bit `0x1000`** — stated here as a
HYPOTHESIS, on one negative case, not as a law. (Flag semantics are a probe of their own.)

**The rule that IS supported at full strength, and belongs in AGENTS.md:** drive an engine
dialog button with a click AND a Return fallback, and print which one worked. One of them
silently does nothing, and a suite that clicks once and then checks the filesystem cannot
tell "the button refused" from "the click did nothing".

### 7.2 The dialogs, for whoever needs them next

* `GameMenu` (F10) — `s.S.ave Game`, `l.L.oad Game`, `p.P.ause`/`r.R.esume` (complementary).
* `SaveGame` — edit box is `type=8` and **carries readable text**, pre-filled with the last
  save's name; buttons `s.S.ave` / `d.D.elete` / `c.C.ancel`.
* `LoadGame` — `l.L.oad` / `c.C.ancel`. **The file-list rows carry no text at all** in the
  engine's dialog walk, so a specific save cannot be named by reading the list; the suite
  makes the folder unambiguous on disk instead (and puts every other save back afterwards).
* `OkCancel` — the overwrite confirmation, *"Replace the contents of game .slctl.?"*.
* Hotkeys live INSIDE the strings, so every match is on the letters: `s.S.ave` → `sSave`.

### 7.3 Typing into an engine edit box

`Send-ScKey -Char` posts WM_KEYDOWN **and** WM_CHAR and this edit control honours both:
`slprobe` arrived as `ssllpprroobbee`, read out of the engine's own control text. The
character path now posts WM_CHAR alone. `Send-ScText` is new in this task and had no
callers on `main`, so this was a bug caught before it shipped rather than a latent fault
under existing suites — but it is only visible at all because the check reads the ENGINE's
control text instead of trusting the variable the script typed from.

---

## 8. Evidence index

| what | where |
| --- | --- |
| control arm (arm 1) | `C:\sc-work\logs\offscreen\20260812-224315-test-save-load.txt` |
| fanout arms (2, 3, 5, 6) | `C:\sc-work\logs\offscreen\20260812-225530-test-save-load.txt` |
| crossload arm (4) | `C:\sc-work\logs\offscreen\20260812-225927-test-save-load.txt` |
| dialog probe | `C:\sc-work\logs\offscreen\20260812-223339-probe-save-load-dialogs.txt` |
| plugin logs (per phase) | `C:\sc-work\logs\051\save-load-{control,fanout,crossload}.log` |
| per-arm snapshots (JSON) | `C:\sc-work\logs\051\snap-arm*.json` |
| frames (diagnostic, never committed) | `C:\sc-work\logs\051-frames\` |

Frames are on the gitignored path and are not committed — they reproduce game artwork
(AGENTS.md hard rule 1).
