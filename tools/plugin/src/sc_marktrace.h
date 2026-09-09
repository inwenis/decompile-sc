// Dirty-marker trace: every rect the engine hands to the dirty-grid marker
// 0x0041E0D0, with the caller that issued it. A diagnostic, off unless
// %SCPLUGIN_MARKTRACE% opts in, and silent until a 'marktrace-on' marker label
// arms it ('marktrace-off' disarms and prints the per-caller totals).
#ifndef SC_MARKTRACE_H
#define SC_MARKTRACE_H

#include <windows.h>

bool ScMarkTraceWanted(void);
void ScMarkTraceInstall(BYTE* moduleBase, bool writeAllowed);
void ScMarkTraceRemove(void);
void ScMarkTraceOnMarker(const char* label);

#endif // SC_MARKTRACE_H
