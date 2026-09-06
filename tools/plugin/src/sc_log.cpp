// sc_log.cpp -- see sc_log.h.
//
// Lifted verbatim (bar the rename LogLine -> ScLog) out of task 008's scplugin.cpp
// so the fan-out hooks can log through the same file handle and the same lock. The
// special exit-path locking is task 008's, and its reason still holds: blocking on a
// critical section whose owner the OS has already terminated hangs the game on exit.
// What task 023 changed is what happens when the lock cannot be had -- see ScLog.

#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "sc_log.h"

// How long the process-exit path waits for the log lock before writing without it.
// A live owner holds it for microseconds; a dead one holds it forever, and the cap is
// what keeps game exit from hanging on the second case. See the block in ScLog.
#define SC_LOG_EXIT_WAIT_MS  250
#define SC_LOG_EXIT_SLICE_MS 5

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

    // THE EXIT PATH USED TO DROP THE LINE HERE, AND THAT COST A REAL TEST ASSERTION.
    //
    // What happened (task 021 found it, task 022 found the mechanism, task 023 fixed it):
    // one run's detach produced NO log output at all -- not `STATS`, not `GROUPSTATS`, not
    // `CIRCLES stats`, not even `DETACH`. test-selection-circles asserts on that CIRCLES
    // line, so the suite failed against a plugin that had done nothing wrong.
    //
    // "No output at all" is the diagnostic detail that decides the fix. A TRANSIENT overlap
    // with the observer thread would have lost one line and let the next one through; losing
    // every line of the sequence means the critical section was owned and STAYED owned. On
    // the process-exit path that is exactly what happens: Windows terminates every other
    // thread first, and a thread killed inside WriteFile/FlushFileBuffers -- which is where
    // the observer spends nearly all of its time under this lock -- never releases it. So
    // the section is dead-owned, and no amount of waiting will get it.
    //
    // Hence: wait briefly (a LIVE owner releases in microseconds, and waiting keeps the
    // lines ordered), then write anyway. Writing unlocked is safe on precisely this path and
    // no other -- the try-lock flag is only ever set for lpReserved != NULL, where the OS
    // has already terminated every thread that could race us. The alternative on offer was
    // to soften the test's assertion, which would have thrown away a real oracle to hide a
    // logging bug.
    bool locked = false;
    if (InterlockedCompareExchange(&g_logTryLock, 0, 0)) {
        for (int waited = 0; waited < SC_LOG_EXIT_WAIT_MS; waited += SC_LOG_EXIT_SLICE_MS) {
            if (TryEnterCriticalSection(&g_logLock)) { locked = true; break; }
            Sleep(SC_LOG_EXIT_SLICE_MS);
        }
    } else {
        EnterCriticalSection(&g_logLock);
        locked = true;
    }
    DWORD written = 0;
    WriteFile(g_log, line, (DWORD)len, &written, NULL);
    FlushFileBuffers(g_log);  // so the log is readable live while the game runs
    if (locked) LeaveCriticalSection(&g_logLock);
}

// ---------------------------------------------------------------------------
// Test seam (hooktest part [12]) -- lets a test own the log lock from another
// thread so the exit path above can be driven with the lock genuinely held.
// Not called by the plugin.
// ---------------------------------------------------------------------------
bool ScLogTestTryHoldLock(void) {
    if (!g_lockInit) return false;
    return TryEnterCriticalSection(&g_logLock) != 0;
}

void ScLogTestReleaseLock(void) {
    if (g_lockInit) LeaveCriticalSection(&g_logLock);
}

void ScLogTestClearTryLock(void) {
    InterlockedExchange(&g_logTryLock, 0);
}

void ScHexDump(const BYTE* p, int n, char* out, int outLen) {
    int used = 0;
    out[0] = '\0';
    for (int i = 0; i < n && used + 3 < outLen; ++i) {
        used += _snprintf(out + used, outLen - used, "%02X", p[i]);
    }
}

void ScThreadCheck(const char* site, DWORD* seen) {
    DWORD tid = GetCurrentThreadId();
    if (*seen == tid) return;
    ScLog("THREADCHECK %s tid=%u%s", site, (unsigned)tid,
          *seen ? " CHANGED -- the single-thread claim this fix rests on is broken" : "");
    *seen = tid;
}
