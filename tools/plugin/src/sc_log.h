// sc_log.h -- the plugin's log file. Shared by the observer and the fan-out hooks.
//
// Destination: %SCPLUGIN_LOG%, default C:\sc-work\logs\sc-plugin.log. Both are
// outside the repo and C:/sc-work/ is gitignored, so captured game state is never
// committed (AGENTS.md hard rule 1).

#ifndef SC_LOG_H
#define SC_LOG_H

#include <windows.h>
#include <stddef.h>

void ScLogOpen(void);
void ScLogClose(void);

// Switches the log to a BOUNDED-wait lock: used only on the process-termination
// detach path, where the lock's owner may already have been killed by the OS while
// holding it. In that mode ScLog waits SC_LOG_EXIT_WAIT_MS for the lock and then
// writes WITHOUT it rather than dropping the line -- see the block comment in ScLog
// for why dropping cost a real test assertion and why writing unlocked is safe on
// that path alone.
void ScLogSetTryLock(void);

void ScLog(const char* fmt, ...) __attribute__((format(printf, 1, 2)));

// Copy a NUL-terminated string out of GAME memory into a log line, one guarded byte at
// a time, replacing anything a parser could trip over ('|', a quote, a control
// character) with '.'. Dialog text is game data: a stray newline in it would corrupt the
// line a .ps1 suite is about to read. Stops at the NUL, at outLen-1, or at the first
// byte that is not readable.
void ScLogCopyText(DWORD addr, char* out, size_t outLen);

// Resolves %SCPLUGIN_LOG% (or the default) into `out`.
void ScLogResolvePath(char* out, size_t outLen);

// --- test seam (hooktest part [12]); not called by the plugin ---------------
bool ScLogTestTryHoldLock(void);   // take the log lock, as a foreign owner would
void ScLogTestReleaseLock(void);
void ScLogTestClearTryLock(void);  // undo ScLogSetTryLock, so a test can run both modes

// Bytes -> "5589EC" into `out`, truncated rather than overrun. Every caller is building
// a log line out of engine bytes it is about to quote (a hook prologue, a patch site),
// which is why it lives next to ScLog rather than in each of them.
void ScHexDump(const BYTE* p, int n, char* out, int outLen);

// One THREADCHECK line the first time a named site runs, and again if the thread ever
// changes under it. Two modules hold cross-frame state that is only safe because the game
// thread is the only writer; this is the assertion that says so out loud.
void ScThreadCheck(const char* site, DWORD* seen);

#endif // SC_LOG_H
