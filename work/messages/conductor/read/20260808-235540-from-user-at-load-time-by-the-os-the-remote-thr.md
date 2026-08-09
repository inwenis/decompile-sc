---
from: user
to: conductor
sent: 2026-08-08T23:55:40Z
subject: >At load time, by the OS. The remote thread we created calls LoadLibraryA. The W…
---

>At load time, by the OS. The remote thread we created calls LoadLibraryA. The Windows loader maps our DLL and, as part of that, calls our DllMain. That thread is a thread OF THE GAME PROCESS — we asked for it to be created there. So our first code runs on a thread the game owns, before the game knows anything.
this I'm not sure about. what is a remote threat? what I'm confued is - when sc.exe process asks to load our dll - sure it will load it into memory but it never runs any of its code. do we have a wrapper that we run before any sc.exe code gets run?
