---
from: 075
to: conductor
sent: 2026-08-14T08:01:08Z
subject: PR ready: window scale + mouse lock (issue #114)
---

PR: https://github.com/inwenis/decompile-sc/pull/119

Root cause: the normal shortcut presents through WMode, not cnc-ddraw (only the wide
shortcut had moved). WMode has no export table/config, so it structurally cannot scale
or lock the cursor. Switched the normal launcher to cnc-ddraw (already proven live via
wide) with a new deploy-only ini (cnc-ddraw-2x.ini). Offscreen/dev ini and every
existing caller untouched by construction (new -WindowedHelperIni param defaults to
old path).

Both acceptance criteria measured live (GetWindowRect/GetClipCursor read back from the
running process, not from ini contents):
- 2x scale: client 1280x960 (2x the 640x480 requested).
- Mouse lock: GetClipCursor matches the window client rect -- but only AFTER the first
  click inside the window, not on activation alone. Read cnc-ddraw's own source at the
  pinned tag to find that: mouse_lock() at WM_ACTIVATEAPP is gated on !windowed; the
  only unconditional trigger for a plain window is a button-up click inside it.
  Corrected a stale comment in cnc-ddraw.ini that assumed activation-triggered lock
  (text-only, no key/value change).

Offscreen harness: probe-widescreen-present.ps1 (the suite that actually exercises the
touched cnc-ddraw path) passes clean, exit 0, both FOLLOW verdicts unchanged from task
065's baseline.

Separate finding, filed as its own issue rather than blocking this PR: test-selection-
circles.ps1 fails offscreen at an unrelated map-browser step. Reproduced identically on
main HEAD with none of this branch's changes -- pre-existing, not a regression here,
but it looks like it affects ~35 files that use Select-ScBrowserMap, i.e. most of the
suite. https://github.com/inwenis/decompile-sc/issues/118

Not deployed -- ready for review/merge+deploy per the standing duty.
