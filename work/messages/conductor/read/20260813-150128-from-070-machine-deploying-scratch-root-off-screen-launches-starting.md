---
from: 070
to: conductor
sent: 2026-08-13T15:01:28Z
subject: Machine: deploying scratch root + off-screen launches starting
---

Plan: (1) deploy.ps1 to scratch root C:\sc-deploy\scratch-task070 (refuses if any StarCraft is running, takes launch lock). (2) Off-screen probe runs against that scratch tree: probe-framebuffer-capture Stage2 with cnc-ddraw presenting, then a new driven-session suite. No touch of C:\sc-deploy\starcraft-modded, no visible window, no registry writes. Task 069 noted as live-but-gameless; tell me if anything contends for the machine.
