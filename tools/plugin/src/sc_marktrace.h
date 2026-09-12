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

// %SCPLUGIN_CURSOR_POSTED%=1 (run-offscreen.ps1 exports it; run-with-plugin.ps1 gates it
// per launch): the engine's GetCursorPos import answers with the cursor LAYER's own
// position, which follows posted WM_MOUSEMOVE, so the real mouse cannot pan the camera
// through the edge-scroll. Poll re-asserts the slot: cnc-ddraw rewrites the same
// import at its own init, after this plugin attached.
void ScCursorPostedInstall(BYTE* moduleBase, bool writeAllowed);
void ScCursorPostedPoll(void);
void ScCursorPostedRemove(void);
void ScMarkTraceOnMarker(const char* label);

#endif // SC_MARKTRACE_H
