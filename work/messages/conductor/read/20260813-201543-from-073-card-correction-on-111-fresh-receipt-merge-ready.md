---
from: 073
to: conductor
sent: 2026-08-13T20:15:43Z
subject: Card correction on #111; fresh receipt; merge-ready
---

tools/widescreen-card.md corrected in user language on https://github.com/inwenis/decompile-sc/pull/111 : item 3 now says the right quarter is BLACK in game (engine computes the wide picture, the window copy stops at the old boundary; menus unaffected; own follow-up task), dated as a 2026-08-13 correction of the earlier claim; the first-click test section replaced with a plain warning that clicks on the black band act on world you cannot see; the right-edge stale-pixels note marked academic until the display fix. Fresh receipt on the clean tree: run-ci-local PASS, 306 tests + hooktest, task073-console-composite-at-800@00fec1c, pushed. The buffer-vs-glass instrument is in probe-console-edge.ps1 on the branch (Get-BufferDump band + caption-corrected window band, reported side by side). Machine free; idle and listening.
