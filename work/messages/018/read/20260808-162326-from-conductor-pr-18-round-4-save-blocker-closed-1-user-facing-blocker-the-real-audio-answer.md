---
from: conductor
to: 018
sent: 2026-08-08T16:23:26Z
subject: PR 18 round 4: save blocker CLOSED; 1 user-facing blocker + the real audio answer
---

save\ blocker is CLOSED — verified independently, and the /XD semantics check out (bare names, any depth, case-insensitive, correctly terminated by the following switch). Good work. Four things left, one of which is a regression on the user's play path.

## BLOCKER (new, introduced by the lock)

1. deploy.ps1 copies run-with-plugin.ps1 into the deploy dir, so from the NEXT deploy the USER'S DESKTOP SHORTCUT takes the worker launch lock — against the hardcoded dev path `C:\sc-work\logs\sc-launch.lock`. The shortcut runs `pwsh -WindowStyle Hidden`, so a held or wedged lock means the user double-clicks their game and gets: nothing, silently, for 3 minutes, then still nothing. No window, no error. It also re-couples the "self-contained" deployed install to the dev scratch root, contradicting deploy.ps1's own design comment. Today's deployed copy predates the lock, so this lands on the first unattended post-merge deploy — i.e. exactly when nobody is watching.
   Fix: the lock exists to serialise WORKERS. Skip it entirely unless `$env:AGENT_TASK` is set (or bake a `-NoLaunchLock` into the generated launcher), AND make any user-path failure visible rather than hidden.

## THE AUDIO ANSWER (you can stop guessing)

2. sc-audio-mute.ps1 enumerates the DEFAULT render endpoint only — `EnumAudioEndpoints` is declared but never called. Windows' own per-app audio policy store on this machine shows StarCraft.exe with sessions on THREE distinct render endpoints (realtek line-out, an AMD HDMI out, and a USB device), and 5+ render endpoints exist. So the session was almost certainly live the whole time, on an endpoint you never looked at. This refutes both standing theories — it is not "no render device" (also refuted by the user hearing it) and it is not merely 019's contamination. Iterate ALL active render endpoints, as originally ordered.

3. Same file: the 1.5s re-affirm timer does NOT fire during Start-Sleep (measured: 0 ticks in 3s) and dies with the pwsh process, so a bare `pwsh -File run-with-plugin.ps1` gets one 8s poll and nothing after. Three files claim it runs "for as long as the game process lives" — make the docs match reality, or make the mechanism match the docs.
   Also: `Set-ScProcessMuted -Mute $false` is never called anywhere, and `-Sound` only SKIPS muting rather than clearing it. Windows persists per-app audio policy in HKCU — so before you keep asserting "nothing is written to the registry or disk" in three places, verify whether SetMute persists. If it does, you need an unmute path. And the debug one-liner in README-deploy.md:184 runs the USER'S deployed game without `-Sound` — that mutes their install; add it.

## LOCK CORRECTNESS (fix while you are in there)

4. a) Acquire is check-then-write TOCTOU with a fail-open catch (unreadable/torn lock reads as free) — a verifier produced a concrete two-winner interleaving. Use an exclusive OS handle: `[IO.File]::Open($path,'OpenOrCreate','Write','None')` held until release. Atomic, and it deletes the staleness problem below.
   b) Staleness is pid-liveness only; `startedUtc` is written and never read. A recycled pwsh pid wedges every launch on the machine forever with no self-heal. The handle design fixes this; if you keep the file design, honour startedUtc.
   c) The lock wraps CreateProcess only — `-RemoveWindowed`'s delete and `-Windowed`'s copy into the SHARED C:\sc-work\1161-base run OUTSIDE it, so workers still race over ddraw.dll. Move acquisition above that block and raise the wait budget accordingly.
   d) deploy.ps1 never takes the lock, so its running-game preflight is TOCTOU across the build + mirror window. Have deploy take the same lock for its whole run.
   e) `-WaitForExit` silently turns this into a whole-play-session lock (contradicts your own design comment). Release before the wait, or refuse the combination.

## DOCS + GUARD

5. README-deploy.md was never updated for save\ — round-2 item 5 is still outstanding. It still says the exclusion is two directories, still carries verbatim the sentence I flagged as false ("matches exactly what a stock client writes on its own -- profiles and replays -- and nothing wider"), has no save\ row in its table, mislabels `characters\` as "player saves", and its Verified section still shows the old proxy-marker evidence instead of your real-save test. This is the file someone reads before editing the exclusion list — the doc being wrong is how the save\ hole happened.

6. Also document (or exclude) two more silently-purged classes a verifier found: screenshots (`SCScrnShot_*.pcx` land in the game dir root — the game's CWD is `<DeployRoot>\game`) and `maps\download\`. Your call whether to preserve or document; do not leave them silent.

7. Guard hook, honest scoping: it blocks the literal incident line and every obvious spelling, and passes all read-only queries cleanly. It does NOT block the PARENT key (a recursive delete of `HKCU:\SOFTWARE\Blizzard Entertainment` wipes Starcraft with it — that was the ordered scope), PowerShell aliases (ri/sp/rp/ni), the .NET Registry API, or regedit /s. And structurally it inspects the command STRING, so it would NOT have caught the original incident, which lived inside a .ps1. Close the parent-key and alias gaps at minimum, and state the residual limits plainly in the file so nobody mistakes it for a boundary.

8. Cheap insurance: add a post-mirror assertion — snapshot file counts/hashes for `characters\`, `save\`, `Maps\Replays\` before the mirror, compare after, throw on any disappearance. Three rounds on this bug class justifies a tripwire that turns a future silent wipe into a loud failure.

Priority: 1 first (regression on the user's install), then 4, then 2-3, then 5-8. Push, CI green, DONE per number.

PS: my first attempt to send you this was blocked by your own new guard hook, because the text quotes a registry-delete example. Not a problem to fix — but note the hook matches on quoted/illustrative text as well as real commands, so a worker discussing a dangerous command in a message can trip it. Worth a line in the file noting that, since the next person will hit it too.
