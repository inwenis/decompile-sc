// sc_log.cpp -- see sc_log.h.
//
// Lifted verbatim (bar the rename LogLine -> ScLog) out of task 008's scplugin.cpp
// so the fan-out hooks can log through the same file handle and the same lock. The
// try-lock behaviour on process exit is task 008's and is kept for the same reason:
// blocking on a critical section whose owner the OS has already terminated hangs
// the game on exit.

#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "sc_log.h"

static HANDLE g_log = INVALID_HANDLE_VALUE;
static CRITICAL_SECTION g_logLock;
static volatile LONG g_logTryLock = 0;
static bool g_lockInit = false;

static void EnsureDirectoryTree(const char* filePath) {
    char dir[MAX_PATH];
    lstrcpynA(dir, filePath, MAX_PATH);
    char* slash = strrchr(dir, '\\');
    if (!slash) return;
    *slash = '\0';
    // Create each component in turn; CreateDirectoryA on an existing dir is a
    // harmless ERROR_ALREADY_EXISTS.
    for (char* p = dir; *p; ++p) {
        if (*p == '\\' && p != dir && *(p - 1) != ':') {
            *p = '\0';
            CreateDirectoryA(dir, NULL);
            *p = '\\';
        }
    }
    CreateDirectoryA(dir, NULL);
}

void ScLogResolvePath(char* out, size_t outLen) {
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_LOG", out, (DWORD)outLen);
    if (n == 0 || n >= outLen) {
        lstrcpynA(out, "C:\\sc-work\\logs\\sc-plugin.log", (int)outLen);
    }
}

void ScLogOpen(void) {
    if (!g_lockInit) {
        InitializeCriticalSection(&g_logLock);
        g_lockInit = true;
    }
    char path[MAX_PATH];
    ScLogResolvePath(path, sizeof(path));
    EnsureDirectoryTree(path);
    g_log = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                        NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
}

void ScLogSetTryLock(void) {
    InterlockedExchange(&g_logTryLock, 1);
}

void ScLogClose(void) {
    if (g_log != INVALID_HANDLE_VALUE) CloseHandle(g_log);
    g_log = INVALID_HANDLE_VALUE;
}

void ScLog(const char* fmt, ...) {
    if (g_log == INVALID_HANDLE_VALUE || !g_lockInit) return;

    SYSTEMTIME st;
    GetLocalTime(&st);

    char body[2048];
    va_list ap;
    va_start(ap, fmt);
    _vsnprintf(body, sizeof(body) - 1, fmt, ap);
    va_end(ap);
    body[sizeof(body) - 1] = '\0';

    char line[2200];
    int len = _snprintf(line, sizeof(line) - 1,
                        "[%04u-%02u-%02u %02u:%02u:%02u.%03u] %s\r\n",
                        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute,
                        st.wSecond, st.wMilliseconds, body);
    if (len < 0) return;
    line[sizeof(line) - 1] = '\0';

    if (InterlockedCompareExchange(&g_logTryLock, 0, 0)) {
        if (!TryEnterCriticalSection(&g_logLock)) return;
    } else {
        EnterCriticalSection(&g_logLock);
    }
    DWORD written = 0;
    WriteFile(g_log, line, (DWORD)len, &written, NULL);
    FlushFileBuffers(g_log);  // so the log is readable live while the game runs
    LeaveCriticalSection(&g_logLock);
}
