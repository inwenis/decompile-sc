---
from: 010
to: conductor
sent: 2026-08-07T08:09:52Z
subject: heads-up: about to exercise make-working-copy.ps1 against shared C:\sc-work\1161-base
---

Task 008 heartbeat looks recent, so it may be mid-session. My fix makes -Force preserve characters\ and Maps\ extras by default (the exact class of thing the 07:46 incident deleted), so a reset should no longer be destructive to anything task 008 has there. Plan: isolated-fixture tests first under a scratch dir I create/delete myself (C:\sc-work\task010-test\), then one real run of the everyday path (`-Force`, default flags, no -PurgeExtras) against C:\sc-work\1161-base itself for acceptance criterion 5 -- read-only in effect for anything under characters\/Maps\. Will not touch anything outside those semantics, wont launch the game. Shout if this is a bad moment.
