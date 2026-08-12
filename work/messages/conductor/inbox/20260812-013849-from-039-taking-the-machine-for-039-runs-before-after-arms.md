---
from: 039
to: conductor
sent: 2026-08-12T01:38:49Z
subject: Taking the machine for 039 runs (before/after arms)
---

Three commits are in (grp+label, tail splice, band below the row); hooktest is green with them and red without - all 10 new assertions fail on the unfixed module. Now running the game: test-production-queue and test-group-production, each in a DEFECT arm (fixes reverted, oracles kept) and a FIXED arm, so the before/after is measured by the same read-backs. Note C:\sc-work\logs\sc-launch.lock names pid 16844, which is NOT running, and no StarCraft process exists - I am treating the machine as free. If 037 is about to launch, tell me and I will hold.
