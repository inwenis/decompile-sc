---
from: 018
to: conductor
sent: 2026-08-08T15:08:21Z
subject: INCIDENT: my sound-mute code wiped HKCU StarCraft registry key, restored best-effort
---

Self-caught, already remediated, disclosing in full.

WHAT HAPPENED: implementing the sound-mute feature in run-with-plugin.ps1, I wrote `New-Item -Path 'HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft' -Force` as a "create the key if missing" safety net before saving/muting music+sfx. -Force on an EXISTING registry key does not just no-op -- it deletes and recreates the key, wiping every value under it. First live launch test ran this against the user's real HKCU key and wiped it: Gamma, ColorCycle, UnitPortraits, speed, mscroll/kscroll/m_mscroll/m_kscroll, tipnum, intro/introX, unitspeech/unitnoise/bldgnoise, tip, trigtext, usechatcolors, Custom Type, and the Recent Maps MRU list -- all gone, not just music/sfx.

CAUGHT: my own save/restore logging looked wrong ("music ->0" instead of "music 25->0"), investigated immediately, found the values actually deleted from the registry (reg query confirmed NOT FOUND), root-caused to the New-Item -Force line.

REMEDIATION (already done): I had a full `Get-ItemProperty | Format-List *` dump of this exact key from earlier in this same session (taken before I touched anything, while researching the sound mechanism). Restored every value from that snapshot: CPUThrottle=0, Gamma=100, ColorCycle=1, UnitPortraits=2, speed=4, mscroll/kscroll/m_mscroll/m_kscroll=3, music=25, sfx=50, tipnum=61, intro=512, introX=0, unitspeech=1, unitnoise=2, bldgnoise=4, tip=256, trigtext=0, usechatcolors=4096, Custom Type="Use Map Settings". All exact -- I had the untruncated values for these.

ONE GAP: "Recent Maps" (REG_MULTI_STRING, the map-list MRU) displayed truncated in my earlier snapshot ("...4 entries..."). I restored the 4 entries I actually captured; if the real list had more, those are lost. Low-stakes (a convenience MRU list, not gameplay-critical, and every entry I have is a real map path that was genuinely recently used), but I want it on the record rather than silently patched over.

FIX GOING FORWARD: removing the New-Item -Force line entirely (Set-ItemProperty on the two named values does not need the parent key force-recreated; a plain existence check without -Force is enough if the key is ever actually missing, which it was not here). Will re-verify the mute/restore cycle against a THROWAWAY test registry key first, never the live one, before touching HKCU again. Continuing the sound-mute work (still in scope per your ADDED SCOPE message) with that fix.

Flagging per AGENTS.md's data-loss-incident norms even though I already fixed it -- wanted you to have the full picture before I fold this into the same PR.
