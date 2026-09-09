// sc_log.cpp -- see sc_log.h.
//
// Every hook logs through this one file handle under this one lock, so lines from all
// threads interleave whole and in order. The process-exit path takes the lock on
// different terms, because there the owner may be dead -- see ScLog.

#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "sc_engine.h"
#include "sc_log.h"

// Cap on the process-exit path's wait for the log lock before it writes unlocked: a dead
// owner never releases, so an unbounded wait there would hang game exit. See ScLog.
#define SC_LOG_EXIT_WAIT_MS  250
#define SC_LOG_EXIT_SLICE_MS 5

static HANDLE g_log = INVALID_HANDLE_VALUE;
static CRITICAL_SECTION g_logLock;
static volatile LONG g_logTryLock = 0;
static bool g_lockInit = false;

// What a line costs the thread that writes it (lock wait included), so the frame-timing
// line can say how much of a stall was the log itself. Updated under the lock; the
// present hook reads the totals lock-free, which 32-bit counters make safe.
static LONGLONG g_logQpf = 0;
static unsigned g_logLines = 0, g_logSumUs = 0, g_logMaxUs = 0;   // since the last Take
static unsigned g_logTotalLines = 0, g_logTotalUs = 0;           // since open

static void EnsureDirectoryTree(const char* filePath) {
    char dir[MAX_PATH];
    lstrcpynA(dir, filePath, MAX_PATH);
    char* slash = strrchr(dir, '\\');
    if (!slash) return;
    *slash = '\0';
    // CreateDirectoryA on an existing directory fails harmlessly with
    // ERROR_ALREADY_EXISTS, so each component can be created blind.
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
    LARGE_INTEGER f;
    g_logQpf = QueryPerformanceFrequency(&f) ? f.QuadPart : 0;
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

    // On the exit path this lock can be DEAD-OWNED, not merely contended: Windows
    // terminates every other thread before detach, and the observer thread spends nearly
    // all its time inside WriteFile under this lock -- killed there, it
    // never releases it. A transient overlap loses one line; a dead owner loses every line
    // of the detach sequence, including the CIRCLES line test-selection-circles asserts on
    // -- do not soften that assertion, it is a real oracle over a real logging bug. So wait
    // briefly (a live owner releases in microseconds, and waiting keeps lines ordered), then
    // write anyway: unlocked is safe here only because the plugin sets the try-lock flag
    // solely for lpReserved != NULL, where no thread survives to race us.
    LARGE_INTEGER t0, t1;
    QueryPerformanceCounter(&t0);
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
    // Not flushed: the OS cache serves every other reader the moment WriteFile returns,
    // and a crash of the game does not lose cached data. A FlushFileBuffers per line
    // puts the game thread behind the disk for every line -- a millisecond each, with a
    // tail of a tenth of a second and more -- which is a hitch a player feels.
    QueryPerformanceCounter(&t1);
    if (g_logQpf) {
        const unsigned us = (unsigned)(((t1.QuadPart - t0.QuadPart) * 1000000) / g_logQpf);
        ++g_logLines;
        g_logSumUs += us;
        if (us > g_logMaxUs) g_logMaxUs = us;
        ++g_logTotalLines;
        g_logTotalUs += us;
    }
    if (locked) LeaveCriticalSection(&g_logLock);
}

void ScLogWriteCostTake(unsigned* lines, unsigned* sumUs, unsigned* maxUs) {
    if (g_lockInit) EnterCriticalSection(&g_logLock);
    *lines = g_logLines;
    *sumUs = g_logSumUs;
    *maxUs = g_logMaxUs;
    g_logLines = g_logSumUs = g_logMaxUs = 0;
    if (g_lockInit) LeaveCriticalSection(&g_logLock);
}

void ScLogWriteCostSoFar(unsigned* lines, unsigned* sumUs) {
    *lines = g_logTotalLines;
    *sumUs = g_logTotalUs;
}

// Test seam: lets a test own the log lock from another thread, so the exit path above can
// be driven with the lock genuinely held. Not called by the plugin.
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

void ScLogCopyText(DWORD addr, char* out, size_t outLen) {
    if (!out || outLen < 2) { if (out && outLen) out[0] = '\0'; return; }
    out[0] = '\0';
    if (!addr) return;
    size_t i = 0;
    for (; i + 1 < outLen; ++i) {
        BYTE c = 0;
        if (!ScSafeRead((const void*)(DWORD_PTR)(addr + i), &c, 1)) break;
        if (c == 0) break;
        out[i] = (c < 32 || c > 126 || c == '|' || c == '\'') ? '.' : (char)c;
    }
    out[i] = '\0';
}
