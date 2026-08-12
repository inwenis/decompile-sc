# Task 040 — Test host isolation, so runs stop taking over the user's screen

## Verdict up front

**A route exists that needs zero installs and zero host changes, and it is proven working end to end.** A Windows **invisible desktop** (`CreateDesktop`, a built-in Win32 API — not a VM, not a new user account) hosts the game, renders it correctly, and frame capture still works from it. Measured twice, cleanly. Nothing appears on the visible screen at any point, and nothing persists after the run.

A VM (VirtualBox/VMware) was researched but **not installed and not recommended** — it needs a real install plus a second Windows/Linux license, and a working zero-cost alternative already exists, so there is nothing to trade that cost against.

**Approval gate: nothing to approve.** The recommended route touches no host state — no installer, no new user account, no registry write. What remains is ordinary code work inside this repo (wiring the mechanism into the shared test harness), which goes through the normal PR review flow, not a host-approval flow.

---

## 1. The Windows 11 Home constraint, verified

| check | result | how verified |
|---|---|---|
| Edition | **Windows 11 Home** (SKU `Core`) | `systeminfo` → `OS Name: Microsoft Windows 11 Home`; registry `EditionID = Core`. (`HKLM:\...\CurrentVersion\ProductName` still says "Windows 10 Home" — a known cosmetic lag in that one field on upgraded installs; `systeminfo` and `EditionID` are the authoritative source and agree with each other.) |
| Build | 10.0.26200 (24H2-era) | `systeminfo` |
| Hyper-V management stack | **Confirmed unavailable**, as expected for Home | `systeminfo` → `Hyper-V Requirements: A hypervisor has been detected. Features required for Hyper-V will not be displayed.` — Home ships no Hyper-V feature to enable in the first place |
| CPU virtualization | **Available** (this matters for a VM route, not for the recommended one) | `Get-CimInstance Win32_Processor` → AMD Ryzen 7 4700U, `VirtualizationFirmwareEnabled = True` |
| A hypervisor is already active | **Yes** — Windows' own VBS/Device Guard hypervisor | `systeminfo`: `Virtualization-based security: Status: Running`. Relevant to the VM route (§4): a third-party Type-2 hypervisor must then run alongside it via the Windows Hypervisor Platform API rather than raw VT-x/AMD-V, a known VirtualBox performance factor |
| Machine is physical, not itself a VM | Confirmed | `Win32_ComputerSystem.Model = VivoBook_ASUSLaptop X421IA_M433IA`, board/BIOS vendor = ASUSTeK/AMI |
| VM software currently installed | **None** | Checked `Get-Package`, `C:\Program Files\Oracle\VirtualBox`, `C:\Program Files (x86)\VMware` — none present |

The task's starting assumption ("Hyper-V's management stack is not offered on Home") is correct and now evidenced rather than assumed.

---

## 2. Routes considered

| route | install needed | verdict |
|---|---|---|
| **Invisible Windows desktop** (`CreateDesktop`) | **None** | **RECOMMENDED — proven working (§3)** |
| Hyper-V | N/A | Ruled out — Home has no management stack (§1) |
| RDP into a hidden/disconnected session | N/A | Ruled out — Windows Home has no RDP **host** capability at all (longstanding Microsoft SKU restriction; no live test needed to confirm this) |
| Fast User Switching to a second local account | Creates a new persistent Windows user account | Not pursued — that account creation is itself a write to host state needing the same approval gate as an install, for a heavier mechanism (a whole second logged-in desktop session vs. one extra desktop object) than the route that already works for free |
| Off-screen window positioning (move the window to negative/out-of-bounds coordinates) | None | Not pursued — cheapest possible hack, but fragile (breaks if the external-monitor arrangement changes; this machine already runs two monitors at different offsets) and doesn't stop a brief flash at the window's default position. The invisible-desktop route is strictly better at the same (zero) cost |
| VirtualBox / VMware Workstation Player | **Installer + guest OS** | Desk research only (§4) — not recommended given a free alternative already works |

---

## 3. The recommended route: an invisible Windows desktop

### Mechanism

`CreateDesktop` is a plain Win32 API that creates a second **desktop object** inside the user's existing login session — the same primitive Windows itself uses for the UAC consent prompt and the screen-saver desktop. A process launched onto it runs completely normally (same GPU, same session) but is not the one currently being shown on the monitor. Nothing is installed; nothing persists after the launching process exits.

### Proof, in order

1. **Structural proof (no game involved).** Created a desktop named `SC040TestV2` and compared it against `OpenInputDesktop()` — the API that names whichever desktop is *actually visible* right now. The two are different objects (`'Default'` vs `'SC040TestV2'`). Nothing composites to the physical screen from a desktop that is never switched to, and this script never calls `SwitchDesktop`.
2. **Render + capture proof.** Launched `StarCraft.exe` through the **real production launcher** (`scinject.exe`, extended with a `--desktop <name>` flag — see §5), early-injecting `WMode.dll` exactly the way every existing test suite does via `run-with-plugin.ps1 -InjectWindowedHelper WMode`. This is not a shortcut: the first attempt used the older `ddraw.dll`-copy trick and produced a `0x0`-sized window on *both* the alt desktop and, as a control, the normal visible desktop — proving that failure was a bug in that trick, not in the desktop, before it was abandoned in favor of the real launcher.
   - `PrintWindow` (the same capture primitive `tools/plugin/drive-game.ps1` already uses for every existing test) captured a **640×480 frame**, correct size, 56–61 distinct sampled colors depending on the run (i.e. not blank).
   - Opened the captured frame locally to confirm it is the real StarCraft main menu (Single Player / Multiplayer / Campaign Editor, etc.) — not garbage. Not committed or pushed anywhere: it reproduces game artwork, which this repo's hard rule 1 forbids holding (`AGENTS.md` "Screenshots vs hard rule 1").
   - **Reproduced twice, both clean passes.**

### What is proven vs. what is not yet

| | status |
|---|---|
| The game renders correctly off-screen | **Proven** (§3, twice) |
| A frame can be captured off-screen (`PrintWindow`) | **Proven** (§3, twice) |
| Driving via posted window messages (menu clicks, drag-box) works cross-desktop | **Not yet tested directly.** `PostMessage` sits in the same Windows security family as `PrintWindow` (both are window-handle operations, neither requires the target to be the visible desktop), and `research/automated-testing-options.md` §4.1/§9 already established that posted messages need neither focus nor foreground — so there is good reason to expect this works, but it was not the decisive risk named in this task and was not measured. Flagged as the first thing a follow-up implementation task should verify |
| Wiring this into `run-with-plugin.ps1` / `drive-game.ps1` for real test runs | **Not done.** Every driving primitive in `drive-game.ps1` would need the same `SetThreadDesktop` treatment `PrintWindow` needed here — mechanical (each primitive is already a thin P/Invoke wrapper) but real follow-up work, correctly out of scope for a decision task |

### The fanout-of-parallel-workers concern

Each worker can create its **own uniquely-named** invisible desktop (this task used `SC040Test`/`SC040TestV2`), so N concurrent workers means zero desktop clutter regardless of N — directly answering the Context's "fanout of parallel workers makes it worse."

**One caveat, stated precisely so it isn't oversold:** StarCraft is already single-instance **per machine**, independent of desktops (`research/automated-testing-options.md` §6, and re-confirmed live in this task — an earlier probe's leftover process blocked a later launch with the documented "second launch exits with code 0" behavior). The invisible-desktop route fixes **visibility** of however many runs happen; it does not unlock true concurrent game instances, because that was never available in the first place. `sc-launch-lock.ps1`'s existing serialization is still required and still correct.

---

## 4. VM route (desk research only — not installed, no approval sought)

Not tested live: testing it would require installing a hypervisor, and the task's hard boundary is that nothing gets installed without conductor-relayed user approval. Since the free, zero-install alternative in §3 already works, there was nothing to weigh an install's cost against, so none was requested.

| | |
|---|---|
| Software | VirtualBox or VMware Workstation Player — both free, both installable on Home (the Home restriction is specific to *Microsoft's own* Hyper-V feature, not third-party hypervisors) |
| Currently installed | **No** (checked, §1) |
| Guest OS | Needs a full second Windows install (a licensing question — reusing one retail license across host and guest is against standard Microsoft terms; free evaluation images exist but expire) or a Linux+Wine guest, which sidesteps licensing but makes `scinject.exe`'s `CreateRemoteThread`-based injection an open compatibility question under Wine, not evaluated here |
| A hypervisor is already active on this host | Yes — Windows' own VBS (§1). A Type-2 hypervisor must then run via the Windows Hypervisor Platform API instead of raw hardware virtualization, a documented VirtualBox performance factor in general (not measured on this machine, since nothing was installed) |
| Setup cost | Install hypervisor → install/license a guest OS → install SC 1.16.1 in the guest → port the entire plugin/injection toolchain into the guest → build an artifact pipeline to get screenshots/logs back out to the host. Multi-day integration, not comparable to the near-zero cost in §3 |
| Per-run cost | VM boot/resume time (seconds to tens of seconds depending on snapshot strategy) plus whatever penalty applies to legacy DirectDraw 2D rendering inside a VM — a long-documented category of pain for old games in VMs generally; unverified specifically here since nothing was installed |
| Recommendation | **Not pursued.** If the user wants a real VM anyway, for reasons beyond this specific ask (e.g. a fully separate sandboxed OS), that is a separate, explicit approval-gated request — not something this investigation recommends on its own merits |

---

## 5. What changed in this repo

One small, isolated, backward-compatible addition to `tools/plugin/src/scinject.cpp`: an optional `--desktop <name>` flag that sets `STARTUPINFOA.lpDesktop` explicitly. Unset (every existing caller), behavior is byte-for-byte the same as before. Built and proven working in this task's own worktree; does not touch the shared main checkout or any other concurrent worker's build output.

This was necessary because the alternative — relying on the launched process inheriting its parent thread's current desktop — was tried first and measured **not** to reliably hold through PowerShell's own process-launch path (the game came up on no discoverable desktop at all). Naming the desktop explicitly removed that uncertainty.

---

## 6. Measured runtime impact

| measurement | result |
|---|---|
| Baseline launch (visible desktop, standard `run-with-plugin.ps1 -InjectWindowedHelper WMode`, through the existing health check) | **8.06 s** |
| Invisible-desktop launch + frame capture (this task's probe, full run) | **10.36 s** (reproduced twice: ~10.4 s both times) |
| An actual existing end-to-end test script (`test-selection-circles.ps1`: menu walk, map load, drag-box, plugin-log assertions, teardown), run under standard (visible-desktop) conditions | **75.03 s total** |

The ~2.3 s difference between the two launch numbers is **not** attributable to the desktop-switch mechanism itself (`CreateDesktop`/`SetThreadDesktop` are sub-second OS calls) — it is mostly this task's own probe using a more conservative settle sleep (5 s) than the existing health check (2 s), an artifact of a throwaway probe script, not the route. Measured against a real test script's real 75 s, even taking the full delta at face value is low single digits of a percent, dominated entirely by the game's own menu/map-load time rather than by anything isolation-related.

*(`test-selection-circles.ps1` itself reported one pre-existing, unrelated assertion failure — "[5] the box contained more than 12 units" — during this baseline timing run. That is that test's own existing behavior, not something this task touched or needs to chase; it was run only as a timing reference.)*

---

## 7. The exact steps the user would approve — one read

**Nothing to approve for the recommended route.** It installs no software, creates no account, writes no registry key, and leaves nothing behind after a run (the desktop object is destroyed the moment the launching process exits). What is left is ordinary code work — wiring `--desktop` through `run-with-plugin.ps1` and making `drive-game.ps1`'s driving primitives desktop-aware — which goes through the repo's normal PR review, not a host-approval step.

If, separately, the user wants a genuine VM for reasons beyond this ask, that would be: *"Install VirtualBox (free, ~150 MB download) and set up a guest OS you provide or license."* Not recommended by this investigation, and not requested.

---

## 8. Housekeeping

- No game binaries, frames, or other game-derived content committed (hard rule 1). The one captured frame lives at `C:\sc-work\logs\040-probe\` (gitignored, outside the repo).
- No writes to live user state — no registry touched, no user account created, no persistent host configuration changed (hard rule 5).
- Every probe process was cleaned up; verified no orphaned `StarCraft.exe` after each run.
- Two other workers' games were observed live-running concurrently during this task (via the shared `sc-launch.lock` and process ownership checks) and were correctly left untouched — confirmed each one belonged to a different task before doing anything near it.
- The `--desktop` addition to `scinject.cpp` was built and tested only inside this task's own isolated worktree (`C:/git/decompile-sc-task040`), never touching the shared main checkout's build output.
