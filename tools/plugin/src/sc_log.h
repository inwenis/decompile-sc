// sc_log.h -- the plugin's log file. Shared by the observer and the fan-out hooks.
//
// Destination: %SCPLUGIN_LOG%, default C:\sc-work\logs\sc-plugin.log. Both are
// outside the repo and C:/sc-work/ is gitignored, so captured game state is never
// committed (AGENTS.md hard rule 1).

#ifndef SC_LOG_H
#define SC_LOG_H

#include <stddef.h>

void ScLogOpen(void);
void ScLogClose(void);

// Switches the log to a try-lock: used only on the process-termination detach
// path, where the lock's owner may already have been killed by the OS.
void ScLogSetTryLock(void);

void ScLog(const char* fmt, ...) __attribute__((format(printf, 1, 2)));

// Resolves %SCPLUGIN_LOG% (or the default) into `out`.
void ScLogResolvePath(char* out, size_t outLen);

#endif // SC_LOG_H
