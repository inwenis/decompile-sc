# Testing StarCraft in-game without a human at the keyboard

Task 012. An **investigation**, not an implementation: how can this project verify in-game
behaviour without the user personally loading a map, box-selecting and right-clicking?

Every in-game result so far required them ([`runtime-selection-observations.md`](runtime-selection-observations.md)
§3.1: "a human drove the game, not the harness"). That does not scale to a test suite and it makes
regressions invisible between sessions.

All work below was done on the disposable working copy `C:\decompile-sc-data\sc-work\1161-base`, offline,
single-player, with the conductor's standing permission to launch and kill the game freely. The
pristine install `C:\decompile-sc-data\sc-install\Starcraft` was never opened. After every probe the working copy's
`StarCraft.exe` still hashes `AD6B58B2…88C6A46` — the documented pristine value — and no
`ddraw.dll` or any other file was added to the game directory.

---

## 0. Verdict up front

**Both halves are automatable, and the driving half turned out to be the easy one — the opposite of
what this task expected.**

| | recommendation | verdict | status |
|---|---|---|---|
| **Driving** | Post Win32 window messages to the game's `SWarClass` HWND | **Works — demonstrated live in this task** | new |
| **Observing** | Extend the existing injected plugin into a machine-readable state channel | **Works — the read path is already proven** | extend §008 |
| Stop-gap available today | Script observes, human drives (§5.1) | works, costs one human minute per run | ready |

Three measured results drive that verdict, and two of them overturn a standing assumption:

1. **A posted `WM_LBUTTONDOWN` at client coordinate (513,328) made StarCraft exit.** A second
   posted click at (215,119) opened the *Select Game Type* dialog and moved the game's own rendered
   cursor to that exact point. The game takes the pointer position from the message's `lParam`.
   **A script can click in this game.** ([§4.1](#41-driving-probe-posted-window-messages))
2. **Screen coordinates are not involved at all** in that mechanism, so the coordinate failure that
   killed the previous attempt cannot recur — it is designed out, not fixed. ([§3](#3-the-synthetic-input-failure-diagnosed))
3. **The game denies `PROCESS_VM_READ` to its own user.** An external `ReadProcessMemory`
   observer — the obvious cheap design — is impossible. The injected DLL is not one option among
   several; it is the only general one. ([§4.2](#42-observing-probe-the-game-protects-its-own-process))

Task 011's hard rule 5 ("do not try to drive the game with synthetic input… a worker cannot reliably
click in this game") was correct about `SendInput` and is **wrong about window messages**. That rule
should be narrowed rather than dropped: see [§7](#7-what-this-changes-for-work-already-in-flight).

---

## 1. The two halves, and which one matters

Automating a test has two halves and they are not equally hard:

- **Driving** — making the game do a thing.
- **Observing** — determining what actually happened, in a form a script can assert on.

This task was cut on the assumption that observing is the more valuable and easier half. **The value
judgement holds; the difficulty judgement does not.** Observing is where the remaining work is,
because the addresses we would need to assert on (unit position, current order, order target) are
*not yet verified by this project* — only the selection arrays are. Driving turned out to need no new
reverse engineering at all.

The two halves are independent. Either can be automated alone, and **partial automation is a real
option, not a consolation prize** — see [§5.1](#51-partial-automation-script-observes-human-drives).

---

## 2. Ranked options

Ranked by (confidence × value) ÷ cost. "Cost" is rough worker-task effort, not wall-clock.

### 2.1 Driving

#### D1 — Post window messages to the game HWND ★ recommended

| | |
|---|---|
| Automates | Driving |
| Feasibility | **Proven in this task.** Two independent posted clicks produced two different, correct, observed effects (§4.1) |
| Cost | **Low–medium.** ~1 task. No C++, no injection, no new addresses. The work is a menu coordinate map and a small state machine |
| Can prove | Everything from the window procedure inward: menu navigation, map loading, the real selection-building code (`SortAllUnits`, `combineSelectionsLists`), the real command-generation code (`CMDACT_Select`), the HUD. A box-select driven this way is the same code path as a human's box-select |
| **Cannot prove** | **Anything about the OS input stack below the window proc** — device drivers, raw input, DirectInput, cursor clipping, DPI, multi-monitor. It enters the game one layer *above* where a real click enters Windows. If a bug lives in that layer, this test is blind to it — see [§6](#6-validity-limitations-stated-plainly) |
| Also cannot prove | Behaviour in **fullscreen exclusive** mode. Every probe here ran windowed (`-InjectWindowedHelper WMode`). Fullscreen DirectDraw changes the display mode and the game's cursor handling; posted-message driving there is **[unverified]** |
| Hard constraint found | **The window must not be minimized.** A posted click that worked on a restored window did nothing while iconic (§4.1). The game imports `IsIconic` |
| Hard constraint NOT found | **Focus is not required.** The click that killed the game was posted while a different application held the foreground. Tests do not steal the user's keyboard |

This is the recommendation because it is the only driving option that both works today *and*
exercises the code the project is actually changing.

#### D2 — Drive from inside the process (plugin calls the game's own functions)

| | |
|---|---|
| Automates | Driving |
| Feasibility | Plausible; not probed here. The plugin already runs in-process with a verified address map, and task 011 is already hooking these functions |
| Cost | Medium–high. Every driving primitive is a new hook or a new call with a reconstructed calling convention. `binary-selection-map.md` §5.1 warns that Blizzard's build passes arguments in `ESI`/`EDI`/`EBX` and Ghidra defaults to a stack convention, so each signature must be established by hand |
| Can prove | That the *receive* side behaves: `CMDRECV_Select`, the order-dispatch iterator at `0x0049A850`, the per-player arrays |
| **Cannot prove** | **That a real player action produces the intended command in the first place.** This is not a footnote — it is fatal for the project's north star. The 12-unit truncation happens in the *input* path (`SortAllUnits`'s cap check at `0x0046F208`, `combineSelectionsLists`'s two caps). A test that calls `CMDACT_Select` directly with a hand-built list has skipped exactly the code that does the truncating, and so **cannot demonstrate that fan-out works from a box-select** |
| Verdict | **Use for unit-level probes, never as the end-to-end driver.** D1 costs less and proves more |

#### D3 — Command-stream / replay playback

| | |
|---|---|
| Automates | Driving (partly), and doubles as an oracle (O3) |
| Feasibility | Mechanically sound, operationally awkward. The `.rep` stream *is* the command stream (`selection-cap.md` §6.2), so replaying re-executes commands through the real `CMDRECV_*` handlers |
| Cost | Medium. Plus: **there is no way to start a replay without the menus.** A strings scan of `StarCraft.exe` found no map/replay command-line switch (§4.3) — so this still needs D1 to press the buttons |
| Can prove | Deterministic re-execution of a recorded session; excellent as a **regression fixture** ("this recorded game must still produce this state") |
| **Cannot prove** | Anything about local input handling or command *generation* — a replay contains commands that were already generated. It also cannot exercise a modified `Select` encoding: a replay carrying a >12 select desyncs against a vanilla receiver (`selection-cap.md` §6.2) |
| Verdict | **Second-phase.** Valuable once D1 exists; useless before it |

#### D4 — Scripted maps and saved games as fixtures

| | |
|---|---|
| Automates | Neither, strictly — it automates **setup** |
| Feasibility | Good. `tools/make-test-map.ps1` already builds deterministic `.scx` fixtures (36 Marines, single player, no hostiles) by writing `UNIT` records directly |
| Cost | Low for what exists; medium to add CHK `TRIG` (trigger) support, which the generator does not have — richchk models neither `UNIT` nor `TRIG`, and `UNIT` was hand-rolled (`tools/README-test-map.md`) |
| Can prove | Nothing on its own. It makes the *starting state* reproducible, which is what turns a probe into a test |
| **Cannot prove** | Anything about selection. **Map triggers order units directly** — they never touch `playersSelections`, never build a client selection, never emit a `Select` command. A trigger-driven "36 units moved" result says nothing about the 12-unit cap |
| Verdict | **Adopt as fixtures, reject as a driver.** The distinction matters: a trigger-driven green test would be actively misleading |

#### D5 — Fix synthetic OS input (`SendInput`) ✗ rejected

| | |
|---|---|
| Feasibility | The coordinate bug is diagnosable (§3) and probably fixable |
| Verdict | **Reject anyway**, for three independent reasons, any one of which is sufficient |

1. **It is banned in this repo.** `config/guard-destructive.ps1:123` hard-denies `SendKeys|SendInput|nircmd|CopyFromScreen` for workers, with the reason on record: *"worker 036 tabbed into the human's open Gmail and captured their inbox"*. That is a policy decision taken after a real incident, not a technicality.
2. **It has global side effects by construction.** Synthetic input goes to whatever window has focus and moves the user's real pointer. The user is at their keyboard.
3. **D1 is strictly better.** It needs no screen coordinates, cannot leak to another window, and does not require focus. Fixing `SendInput` would be work spent reaching a worse place.

### 2.2 Observing

#### O1 — In-process memory reads from the injected plugin ★ recommended

| | |
|---|---|
| Automates | Observing |
| Feasibility | **The read path is already proven.** `tools/plugin/src/scplugin.cpp` reads all six selection globals through a `VirtualQuery`-guarded `SafeRead` and logged them correctly through a real game session (`runtime-selection-observations.md` §3) |
| Cost | **Low for what exists, medium to extend.** The gap is not the mechanism, it is the address map — see the honest cost below |
| Can prove | What is selected, how many, in which order, per player; player ids; anything else whose address we verify |
| **Cannot prove** | **Anything we have not mapped.** Today the plugin can assert on *selection* and nothing else. Asserting "these 36 units now have a move order to point X" needs `CUnit` field offsets for order id, order target and position. This project has verified only `sizeof(CUnit) = 0x150`, `CUnit+0x0C` (sprite), `CUnit+0x4C` (player id) and `CUnit+0xA5` (uniqueness). Community sources give the rest; **under this repo's evidence rule they must be re-derived from the binary before any assertion depends on them** |
| Also cannot prove | Anything about what is *drawn*. The HUD is a separate array (`clientSelectionGroup`) and the wireframe row is dialog-control driven (`selection-cap.md` §4.5) — memory agreeing does not mean the screen agrees |
| Known trap | `clientSelectionCount` and `clientSelectionGroup` **disagree during teardown** (§3.4 of the runtime doc). An assertion that reads the count and walks that many slots will occasionally read four NULLs and believe it has four units. Walk and validate the slots |

#### O2 — Assert on the command stream

| | |
|---|---|
| Automates | Observing |
| Feasibility | Good, and cheaper than it looks. `CMDACT_Select` (`0x004C0860`) is the single place the client builds selection commands, and the wire format is confirmed from the binary (`binary-selection-map.md` §6.3): `[u8 id][u8 count][u16 tag]×count`, length `2 + count*2` |
| Cost | Low–medium as an in-process tap; low as offline `.rep` parsing (screp already parses the format) |
| Can prove | **Intent, exactly.** "The client emitted three `Select` commands of 12, 12 and 12 followed by a move order" is a precise, structural assertion — far stronger than reading a screen, and it is the natural oracle for fan-out |
| **Cannot prove** | **That the command had any effect.** A command can be emitted and then dropped: `CMDRECV_Select` silently discards any packet with count > 12. A test that only watches the send side would score a rejected command as a pass. **Pair it with O1, never use it alone** |

#### O3 — External `ReadProcessMemory` from the test script ✗ rejected as designed, viable in one variant

| | |
|---|---|
| Feasibility | **Measured impossible in the obvious form.** StarCraft applies a protected DACL to its own process denying `PROCESS_VM_READ`, `VM_WRITE`, `VM_OPERATION`, `CREATE_THREAD` and `DUP_HANDLE` to Everyone. 3581 `OpenProcess` attempts over 60 s from process start: zero grants (§4.2) |
| The one variant that works | **Be the launcher.** Windows does not re-evaluate an already-open handle when a DACL changes, so the handle `CreateProcess` returns keeps full access. `scinject.exe` relies on exactly this — it injects *after* `WaitForInputIdle`, using rights that a fresh `OpenProcess` cannot obtain. A harness built the same way could read memory forever with **no DLL and no rebuild per assertion** |
| Cost | Medium. It means moving the launcher into the harness |
| **Cannot prove** | Same blind spots as O1 — it is the same reads through a different door |
| Verdict | **Not now.** O1 already works and its cost is the address map, which this shares. Record the trick; it is the right answer if per-assertion DLL rebuilds become the bottleneck |

#### O4 — Screenshot comparison ✗ rejected as an oracle, adopted as a diagnostic

| | |
|---|---|
| Feasibility | **Technically fine, and better than expected.** `PrintWindow(hwnd, dc, PW_CLIENTONLY)` against the game's DirectDraw window returned a correct 640×480 frame while the game ran, twice, with no crash (§4.1). Being window-scoped it cannot capture anything else on the user's desktop |
| **Cannot prove** | Anything *structural*. A pixel diff cannot tell "12 units selected" from "13 units selected"; it tells you pixels changed |
| Why reject as an oracle | Brittle against palette, animation, unit idle frames and the pulsing selection circles; and a committed baseline image would be **game artwork**, which project hard rule 1 forbids the repo to hold |
| Adopt as | A **diagnostic aid**, never committed. It is how this task read the menu coordinates it then clicked, and it is how a failed automated run should be triaged |

#### O5 — A human looks at the screen (status quo)

Still the only thing that proves the *whole* stack, including rendering and the OS input path. It
costs a round trip per assertion and cannot run unattended. **Keep it as the final acceptance gate,
demote it from being the only gate.**

---

## 3. The synthetic-input failure, diagnosed

The previous attempt aimed the pointer at screen `1818,935` and it landed at `1228,1544`
(`runtime-selection-observations.md` §5). That was recorded as "the display is 3840×2160, so suspect
absolute-coordinate normalisation and/or DPI scaling". Measured, on this machine, today:

```
SM_CXSCREEN        = 3840      SM_CXVIRTUALSCREEN = 5760
SM_CYSCREEN        = 2160      SM_CYVIRTUALSCREEN = 2160
SM_CMONITORS       = 2         SM_XVIRTUALSCREEN  = 0 , SM_YVIRTUALSCREEN = 0

\\.\DISPLAY2  primary   rect 0,0-3840,2160     dpi 96x96 (100%)  mode 3840x2160@59Hz
\\.\DISPLAY1  secondary rect 3840,457-5760,1537 dpi 96x96 (100%)  mode 1920x1080@60Hz
```

Three things follow, and they are not the two the original note guessed.

**1. DPI scaling is ruled out.** Both monitors run at 96 DPI, 100 % scale, and the probe process is
DPI-`UNAWARE` — so there is no virtualisation to get wrong. The DPI half of the original hypothesis
is dead.

**2. There are two monitors, and "the display is 3840×2160" was the wrong number.**
`SendInput`'s `MOUSEEVENTF_ABSOLUTE` coordinates are normalised 0–65535 across the **virtual
desktop**, which here is **5760×2160** — 50 % wider than the primary monitor. Normalising against
3840 and letting Windows decode against 5760 (or the reverse) is the classic multi-monitor trap, and
it is present on this machine.

It accounts for the X error, in direction and very nearly in size:

| hypothesis | predicted landing | observed |
|---|---|---|
| encode ÷5760, decode ×3840 | `1212, 935` | `1228, 1544` |
| encode ÷3840, decode ×5760 | `2727, 935` | |
| no mismatch | `1818, 935` | |

`1818 × 3840/5760 = 1212` against an observed `1228` — a 1.3 % discrepancy on an axis that was wrong
by 33 %. **The X failure is a virtual-desktop normalisation bug.**

**3. The Y error is a second, separate fault, and it is not identified. [unverified]**
Virtual and primary height are both 2160, so *no* virtual-vs-primary mismatch can move Y at all —
every hypothesis in the table above predicts Y lands exactly on 935. It landed 609 px low. No
monitor-geometry arrangement tested reproduces that. The original code was never committed (a
repo-wide search finds no `SendInput`/`mouse_event` caller outside the guard's own deny-list), so the
second fault cannot be recovered. Saying "absolute-coordinate normalisation" explains half of this
failure and it would be dishonest to present it as explaining all of it.

**Is it fixable? Yes — and it does not matter.** The correct normalisation is arithmetic:
`round(x × 65535 / (SM_CXVIRTUALSCREEN − 1))` with `MOUSEEVENTF_VIRTUALDESK` set, offset by
`SM_XVIRTUALSCREEN`. The reason to reject that fix is not difficulty:

- The recommended driver ([D1](#d1--post-window-messages-to-the-game-hwnd--recommended)) passes
  **client** coordinates inside `lParam`. There is no screen, no monitor, no DPI, no normalisation
  and no cursor in the path. The entire bug class is absent by construction rather than fixed.
- `SendInput` is banned for workers by `config/guard-destructive.ps1` anyway (§2.1 D5).

---

## 4. What the probes measured

Everything below was run in this task. Scripts are in `work/scratch/012-*.ps1` (gitignored).

### 4.1 Driving probe: posted window messages

Setup: `./tools/plugin/run-with-plugin.ps1 -InjectWindowedHelper WMode` — the corrected windowed
recipe, which writes nothing into the game directory. Window: `class='SWarClass'`,
`rect=1595,784-2245,1301`, client 640×480. Messages posted with `PostMessageA(hwnd, …)`, client
coordinates packed into `lParam`.

| # | posted | window state | result |
|---|---|---|---|
| 1 | `WM_MOUSEMOVE` + `WM_LBUTTONDOWN/UP` at client `(513,328)` = **Exit** | restored, **foreground** | **process terminated** |
| 2 | same, at `(513,328)` | **minimized**, unfocused | **no effect** — process alive |
| 3 | same, at `(513,328)` | restored (`SW_SHOWNOACTIVATE`), **not foreground** | **process terminated** |
| 4 | same, at client `(215,119)` = **Single Player** | restored, foreground | **"Select Game Type" dialog opened; the game's rendered cursor moved to (215,119)** |

Reading the results:

- **Posted input drives the game.** Two different coordinates produced two different correct effects.
- **Position comes from `lParam`, not `GetCursorPos`.** Before probe 4 the game's own cursor was drawn at roughly `(330,275)`; after it, at `(215,119)` — the posted point. Had the game polled the real cursor, the click would have landed on empty space.
- **Focus is not required** (probe 3 vs 1). This is the result that makes unattended testing polite: a test run does not take the user's keyboard.
- **Minimized breaks it** (probe 2). Leave the window restored; it can be behind other windows.
- Consistent with the import table: `StarCraft.exe` imports **no DirectInput at all**, and `GetKeyState` but **not** `GetAsyncKeyState` (`pe-anatomy.md` § Imports). Its input arrives through `GetMessageA`/`PeekMessageA`/`DispatchMessageA`. **Keyboard** posting is therefore plausible on the same grounds but was **not tested — [unverified]**.

`PrintWindow(hwnd, dc, PW_CLIENTONLY)` was used twice to read the menus and returned correct frames
with the game still running afterwards. The images are in `work/scratch/` and are **not committed**:
they reproduce game artwork (project hard rule 1).

### 4.2 Observing probe: the game protects its own process

An external `ReadProcessMemory` observer was the first design tried. `OpenProcess` failed with
`ERROR_ACCESS_DENIED` — same user, same session, non-elevated on both sides. Right by right:

| access right | result |
|---|---|
| `PROCESS_CREATE_THREAD` (0x0002) | **DENIED** |
| `PROCESS_VM_OPERATION` (0x0008) | **DENIED** |
| `PROCESS_VM_READ` (0x0010) | **DENIED** |
| `PROCESS_VM_WRITE` (0x0020) | **DENIED** |
| `PROCESS_DUP_HANDLE` (0x0040) | **DENIED** |
| `PROCESS_QUERY_LIMITED_INFORMATION` (0x1000) | **DENIED** |
| `PROCESS_TERMINATE` (0x0001) | granted |
| `PROCESS_SET_INFORMATION` (0x0200) | granted |
| `PROCESS_QUERY_INFORMATION` (0x0400) | granted |
| `READ_CONTROL`, `SYNCHRONIZE` | granted (owner rights) |

`READ_CONTROL` was granted, so the security descriptor itself could be read rather than inferred:

```
O:S-1-5-21-…-1001
G:S-1-5-21-…-1001
D:P(D;;DCSWRPWPDTLO;;;WD)(A;;0x100701;;;S-1-5-21-…-1001)
```

`D:P` is a **protected** DACL. `(D;;DCSWRPWPDTLO;;;WD)` is a **deny** ACE for **Everyone** covering
exactly `0x0002|0x0008|0x0010|0x0020|0x0040|0x0080` — create-thread, VM-operation, VM-read,
VM-write, duplicate-handle, create-process. The allow ACE grants the owner only `0x100701` =
terminate, set-quota, set-information, query-information, synchronize. Predicted denials and measured
denials match right for right.

This is the game defending itself against memory editors, and it is written into `StarCraft.exe`:
its ADVAPI32 imports are `OpenProcessToken`, `GetTokenInformation`, `AllocateAndInitializeSid`,
`InitializeAcl`, `AddAccessAllowedAce`, `AddAccessDeniedAce`, `FreeSid` (`pe-anatomy.md`) — the exact
API set for building this descriptor. Nothing here is inferred from the import table alone; the
imports explain a descriptor that was read out of the live object.

Timing: polling `OpenProcess(PROCESS_VM_READ)` from the moment the process could be discovered gave
**0 grants and 3581 denials in 60 s**. There is no practical race window for an outside observer.

Two consequences, both load-bearing:

1. **The injected-DLL architecture is not a preference, it is a requirement.** Code inside the process is unaffected by the process's own DACL. Task 008 chose the only door that is open.
2. **The exception is the launcher.** `scinject.exe` performs `VirtualAllocEx` + `WriteProcessMemory` + `CreateRemoteThread` *after* the game has started — using the handle `CreateProcess` gave it, which retains the access it was granted at creation. That is the O3 variant, and its viability is already demonstrated by every successful injection in this repo.

Side effect worth knowing: `Stop-Process` fails on the game, because .NET opens the process with
`PROCESS_ALL_ACCESS`. `TerminateProcess` on a handle opened with exactly `PROCESS_TERMINATE` works.
Any harness that cleans up after itself needs the narrow open.

### 4.3 No headless entry point

`GetCommandLineA` is imported, so a switch parser exists. A full ASCII-string scan of
`StarCraft.exe` (6171 strings ≥ 4 chars) found **no map, replay or game-start command-line switch**.
The only switch-shaped tokens in the image are `/league` and `/stats` (Battle.net chat commands) and
one junk match. Replay vocabulary exists (`/replay `, `maps\replays\`, `LastReplay`,
`Starcraft\SWAR\lang\replay.cpp`) but as in-game console strings, not startup arguments.

**Conclusion: the game cannot be told what to load from the command line.** Every route into a game
goes through the menus, which is why D1 is load-bearing rather than convenient.

*Method limit:* a switch matched character-by-character rather than against a literal string would be
invisible to this scan. **[unverified — absence not proven]**

---

## 5. The recommendation, and what building it involves

### 5.1 Partial automation — script observes, human drives

**Available now, and it should be adopted regardless of what else happens.** It is not a
consolation prize: it removes the least reliable part of the current loop, which is not the clicking
— it is the *reporting*. Today the user clicks and then describes what they saw in prose. A machine
reading `playersSelections` cannot mis-describe it.

- Cost: turn the plugin's prose log into machine-readable snapshots and add a checker script. Well under one task.
- Buys: exact, replayable assertions from a session the user drives in the normal way; one human minute per run instead of a description round trip.
- The marker channel this needs **already exists** — `scplugin.cpp` polls `SCPLUGIN_MARKER` and stamps a labelled line into the log, so a driver can already segment a session into named test cases.

### 5.2 The full recommendation

**Driver: an external PowerShell harness posting window messages. Oracle: the injected plugin,
emitting structured state.** Both halves exist in prototype; neither needs new reverse engineering to
start.

Sketch, enough to cut a follow-up task from:

1. **Structured state channel (observing).** Add a second output to `scplugin.cpp`: one JSON object per changed snapshot, to `%SCPLUGIN_STATE%`. Keep the human log. Include the count, all 12 slots of each array, the non-null count computed independently, all three player ids, and the `ok` bitmask — the plugin already computes every one of these. *Assert on the slots, never on the count alone* (`runtime-selection-observations.md` §3.4).
2. **Driver module (driving).** `Find HWND by class SWarClass in pid` → `Post-Click -X -Y` → `Wait-ForState { … }`. The three primitives this task used, made reusable. Add a guard that refuses to post while `IsIconic`.
3. **Menu route to a loaded game.** The one genuinely fiddly piece: the click sequence from main menu to *Single Player → Expansion → Play Custom → `test-many-units.scx` → OK*. Capture each screen once with `PrintWindow`, read the coordinates, encode as a table. Expect it to be brittle against dialog focus and load timing — poll for a state change rather than sleeping fixed intervals. **This is the part to timebox.**
4. **First end-to-end test.** Load `test-many-units.scx`; post a drag-box (`WM_LBUTTONDOWN` → `WM_MOUSEMOVE` ×N → `WM_LBUTTONUP`) over the 36 Marines; assert the plugin reports a selection of exactly 12 with 12 non-null slots. That is a *regression* test for the vanilla cap and the natural before-picture for task 011's fan-out.
5. **Extend the oracle (the real cost).** To assert "these 36 units received a move order to X", derive and verify `CUnit` offsets for order id, order target and position from the binary, to this repo's evidence standard. **This is the biggest single item in the plan and it is reverse engineering, not scripting.** Everything up to step 4 is deliverable without it.
6. **Then, and only then, `.rep` fixtures (D3).** Once the harness can reach a game, recording and replaying gives cheap deterministic regression cases.

Rough shape: steps 1–4 are one task. Step 5 is its own task. Step 6 is later.

---

## 6. Validity limitations, stated plainly

**A test that does not enter through the real input path proves less than one that does.** Ranked by
how much each option skips, worst first:

| approach | enters at | skips |
|---|---|---|
| Human at the keyboard | hardware | nothing |
| **D1 posted messages (recommended)** | the game's window procedure | the OS input stack: driver, raw input, cursor clipping, DPI, monitor geometry, fullscreen exclusive mode |
| D2 in-process calls | inside the game's own logic | all of the above **plus** the game's input handling **plus** selection building **plus** command generation — i.e. the code the project is modifying |
| D3 replay playback | the command receiver | all of the above plus command generation |
| D4 map triggers | the simulation | everything, including the selection system entirely |

Concretely, for the project's north star:

- A **D1** green run means: a box-select performed the way a player performs it produced these commands and this state. That is a strong claim.
- A **D2** green run means: given a hand-built list of 36 units, the fan-out emitter and the receive path work. It says **nothing** about whether a real box-select ever yields 36 units to fan out — and the truncation happens precisely there.
- A **D4** green run means almost nothing about selection, because triggers never select anything.

Further limits that apply to the whole plan:

- **One machine, one build.** Windows 11 26200, `StarCraft.exe` SHA-256 `AD6B58B2…88C6A46`, two monitors at 100 % scale. The menu coordinate map in particular is 640×480-specific.
- **Windowed only.** Every probe used the early-injected `WMode.dll`. Fullscreen is untested and its cursor handling differs. **[unverified]**
- **Memory is not the screen.** O1 proves what the arrays hold; the HUD reads a *different* array and the wireframe row is dialog-driven (`selection-cap.md` §4.5). "36 units are selected in memory" and "the player can see and command 36 units" are different claims, and only a human currently proves the second.
- **The two selection arrays are not coherent within a frame** — measured at 268 ms of skew (`runtime-selection-observations.md` §3.6). An automated assertion must poll to a stable state or read the array it actually means, not assume they agree.
- **The active player was 1, not 0.** Read the id; do not index `playersSelections[0]`.
- **The game process is single-instance.** A second launch exits with code 0 while the first is alive; the harness must reap the previous run before starting the next. This bit twice during this task.

---

## 7. What this changes for work already in flight

1. **Task 011's hard rule 5 should be narrowed, not deleted.** "Do not drive the game with synthetic input" is correct for `SendInput` and wrong for posted window messages. Suggested wording: *"Do not use `SendInput`/`SendKeys` (banned by `config/guard-destructive.ps1`). Posting window messages to the game's own HWND is permitted and works — see `research/automated-testing-options.md` §4.1."*
2. **"A worker cannot reliably click in this game" is no longer true.** Task 011's one-attempt-per-round-trip verification protocol can be relaxed for iteration. The *final* acceptance gate should stay human — §6 explains what only a human still proves.
3. **`runtime-selection-observations.md` §5's "a future run needs a human at the keyboard, or a fixed input path"** is answered: the fixed input path exists and is not the one that was tried. That document is not edited from this branch, for the same reason it declined to edit `launch-baseline.md` — the correction belongs with the evidence that produced it.

---

## 8. Housekeeping

- **Pristine install untouched.** `C:\decompile-sc-data\sc-install\Starcraft` was never read, written or launched by this task.
- **Working copy unchanged.** `StarCraft.exe` still hashes `AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46`. No `ddraw.dll` was created; the windowed helper is early-injected, never copied.
- **No game process left running.** Verified zero after the final probe.
- **No game content committed.** The two window captures live in `work/scratch/` (gitignored) and are deliberately not committed or attached to the PR: they reproduce game artwork. Built binaries are likewise not committed.
- **Offline, single-player only.** No Battle.net, no multiplayer, no CD key, at any point.
- **The probe scripts are throwaway.** They live in `work/scratch/012-*.ps1` and are not proposed as tooling; the point of this task is the decision, and productionising the driver belongs to the follow-up task described in §5.2.

---

## 9. The foreground question, settled (task 027, 2026-08-09)

Tasks 022/023 concluded that a posted `WM_MOUSEMOVE` is IGNORED while the game window is
not the foreground window, and made every move-posting primitive raise the window first.
That is wrong, and it was costing the user their focus on every unattended run. Task 027
reversed it on two independent kinds of evidence.

### 9.1 The window procedure does not check activation

`StarCraft.exe` `FUN_004d1d70` is the window procedure (Ghidra headless, this binary; it is
the function containing the `GetKeyState(VK_MENU)` call at `0x004d218a` and the `case 0x111`
accelerator hand-off documented in `control-groups.md` §5.2). Its `WM_MOUSEMOVE` case, in
full:

```c
case 0x200:                                       /* WM_MOUSEMOVE */
  DAT_006cddc0._0_1_ = (byte)DAT_006cddc0 | 1;    /* "the mouse moved" bit */
  if ((ushort)lParam < 0x280) _DAT_006cddc4 = lParam & 0xffff;  else _DAT_006cddc4 = 0x27f;
  if ((ushort)(lParam >> 0x10) < 0x1e0) { _DAT_006cddc8 = lParam >> 0x10; return 1; }
  _DAT_006cddc8 = 0x1df;
  return 1;
```

Three stores and a return: the tracked cursor at `0x006CDDC4`/`0x006CDDC8` (clamped to
639/479, i.e. the 640x480 client) and the pending-move bit at `0x006CDDC0`. No foreground
test, no active test. The pump `0x004D1BF0` then acts on that bit unconditionally
(`TEST byte ptr [0x006cddc0],0x1` at `0x004d1c90` → `0x004D1AE0`, which builds a type-3 UI
event from the stored position and clears the bit).

Corroborating: `StarCraft.exe` imports `GetForegroundWindow` and calls it in exactly ONE
place, `0x004eddf0` — a diagnostic that reads the foreground window's TITLE. Nothing on the
input path calls it.

### 9.2 What activation actually does — and why the raise was harmful

The window procedure's `WM_ACTIVATEAPP` case (`case 0x1c`) stores `wParam` into
`DAT_0051bfa8` and calls `0x004d1750` and `0x00421730`:

| address | calls | effect |
|---|---|---|
| `0x004d1750` | `LoadCursorA(NULL,0x7f00)`, `SetCursor`, `GetCursorPos`, `SetCursorPos` | re-asserts the OS cursor |
| `0x00421730` | `ClipCursor` (`[0x004fe37c]`) with `0x006CDDB0` (a RECT) when activating, `NULL` when deactivating | **confines the user's real mouse to the game window** |
| `0x0041d710` | reads `DAT_0051bfa8`, `IsIconic` | returns 0 — *do not draw* — while the app is inactive or minimised |

So every raise (a) trapped the user's mouse and (b) re-synced the game's cursor to the
physical mouse, throwing away the position a posted move had just set.

### 9.3 The live measurement

`tools/plugin/probe-quiet-input.ps1`, one launch, main menu only, oracles that are hashes
of one window region rather than pictures:

| step | button-region fingerprint | reading |
|---|---|---|
| cursor parked at (590,450), game foreground | `FF975A03A546737B` | baseline; region is static |
| posted move onto Single Player, **user's window foreground the whole time** | `271D215ABFB1EF45` | the background move registered **and drew** |
| game raised, then read again | `FF975A03A546737B` | the raise reset the cursor to the physical mouse |

`GetForegroundWindow()` was sampled around every step and never changed while the move was
posted. Two further arms: with the window in the background the animated main menu produced
two different frames 3 s apart (rendering is LIVE in the background under the windowed-mode
helper), and the same control in the foreground also differed (the animation oracle fires,
so the background result means what it says).

### 9.4 How 022 saw the opposite

022's oracle was a captured FRAME of the game's drawn cursor, and §9.2 shows drawing is the
thing activation actually gates (`0x0041d710`). A stock launch — no windowed-mode helper —
therefore freezes its picture while inactive, and a frame taken then shows the cursor where
it last drew, whatever the engine's tracked position now is. The raise also bundled a 400 ms
settle before the first posted move of each activation, on a control task 021 had already
diagnosed as timing-sensitive and fixed by raising waits. Neither of those is "the move was
dropped".

What is claimed here is only what was measured: with no raise anywhere in the harness,
`test-fanout-orders` and `test-selection-circles` — the exact pair 022/023 cited as going
25→0 — are both 0 failures, the drag box captures all 24 units, and the foreground never
changes during either run.

### 9.5 The active-dialog list

`0x006D5E34` is the head of the engine's list of active dialogs, threaded on the BinDlg
`+0x00` "next" link. Evidence: the event dispatcher `0x00419FD0` — the function every input
event reaches — loads it, then walks `[ECX]` calling each entry's `+0x2A` interact handler
until the link is null. Read-only, it gives a suite the dialog set by name, with each
dialog's bounds and its controls' text/bounds (control bounds are LOCAL to the dialog
origin, the same convention `hud-selection-row.md` uses).

The plugin logs it as one `DIALOGS` line per change (`scplugin.cpp ScanDialogs`). Observed
names on a normal run: `MainMenu`, `Login`, `RaceSelection`, `Create`, `TerranRR`,
`Tips_Dlg`, and in-game `Minimap` / `TextBox` / `Stat_F10` / `StatBtn`. That is what
replaced the hardcoded `(200,261)` tips-dialog click: `Tips_Dlg` sits at `128,32,511,287`
with its OK button at local `20,216,123,243`, i.e. client `(199,261)` on this build —
computed now, not assumed.
