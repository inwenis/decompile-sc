// scinject.cpp -- 32-bit launcher + LoadLibrary injector for task 008.
//
// Usage:
//   scinject.exe <game-exe> <plugin-dll> [options]
//     --early-dll <path>   inject this DLL BEFORE the process is resumed
//                          (repeatable; order preserved)
//     --early              inject <plugin-dll> early too, instead of after init
//     --wait-ms N          settle wait after WaitForInputIdle (default 4000)
//     --no-wait-exit       return instead of waiting for the game to exit
//
// Starts the game from its own directory and makes it load our DLL by running
// LoadLibraryA in a remote thread. Nothing is copied into the game directory --
// see tools/plugin/README.md for why that vector was chosen over proxying
// ddraw.dll.
//
// TWO INJECTION POINTS, because they are for different jobs:
//
//   late (default)  -- after ResumeThread + WaitForInputIdle + a settle wait.
//                      Correct for a passive observer: the loader has run, the
//                      game's own modules are up, and nothing is racing.
//   early           -- into the still-suspended process, before ResumeThread, so
//                      DllMain runs before the game's entry point. Required for a
//                      DLL that must hook something during startup -- e.g. the
//                      windowed-mode helper, which has to be in place before
//                      DirectDraw initialises. This is the shape those helper DLLs
//                      are built for (no export table, so they cannot be a ddraw
//                      proxy; a launcher injects them and their DllMain hooks).
//
// Must be built 32-bit: CreateRemoteThread with a LoadLibraryA address taken from
// this process's own kernel32 is only valid when injector and target are the same
// bitness (kernel32 is mapped at the same base in every process of a given
// bitness within a session).

#include <windows.h>
#include <stdio.h>
#include <string.h>

#define MAX_EARLY 8

static int Fail(const char* what) {
    fprintf(stderr, "scinject: %s failed, GetLastError=%lu\n", what, GetLastError());
    return 2;
}

// Runs LoadLibraryA(dllPath) on a remote thread. Returns the resulting HMODULE
// (0 on failure). Works on a suspended process too: the remote thread drives
// LdrInitializeThunk, so the loader is up by the time LoadLibraryA runs.
static DWORD InjectDll(HANDLE hProc, const char* dllPath) {
    size_t bytes = strlen(dllPath) + 1;
    LPVOID remote = VirtualAllocEx(hProc, NULL, bytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remote) { Fail("VirtualAllocEx"); return 0; }

    SIZE_T written = 0;
    if (!WriteProcessMemory(hProc, remote, dllPath, bytes, &written) || written != bytes) {
        Fail("WriteProcessMemory");
        VirtualFreeEx(hProc, remote, 0, MEM_RELEASE);
        return 0;
    }

    FARPROC loadLibrary = GetProcAddress(GetModuleHandleA("kernel32.dll"), "LoadLibraryA");
    if (!loadLibrary) { Fail("GetProcAddress(LoadLibraryA)"); return 0; }

    // LoadLibraryA's real signature (HMODULE(LPCSTR)) is call-compatible with a
    // thread start routine on x86 stdcall: one pointer argument, return in EAX.
    LPTHREAD_START_ROUTINE start = (LPTHREAD_START_ROUTINE)(void*)loadLibrary;
    HANDLE hThread = CreateRemoteThread(hProc, NULL, 0, start, remote, 0, NULL);
    if (!hThread) { Fail("CreateRemoteThread"); VirtualFreeEx(hProc, remote, 0, MEM_RELEASE); return 0; }

    DWORD wait = WaitForSingleObject(hThread, 20000);
    DWORD mod = 0;
    if (wait == WAIT_OBJECT_0) GetExitCodeThread(hThread, &mod);
    else fprintf(stderr, "scinject: remote LoadLibraryA thread did not finish (wait=%lu)\n", wait);
    CloseHandle(hThread);
    VirtualFreeEx(hProc, remote, 0, MEM_RELEASE);
    return mod;
}

static void DirNameOf(const char* path, char* out, size_t outLen) {
    lstrcpynA(out, path, (int)outLen);
    char* slash = strrchr(out, '\\');
    if (!slash) slash = strrchr(out, '/');
    if (slash) *slash = '\0'; else lstrcpynA(out, ".", (int)outLen);
}

int main(int argc, char** argv) {
    if (argc < 3) {
        fprintf(stderr,
            "usage: scinject.exe <game-exe> <plugin-dll> [--early-dll <path>]... "
            "[--early] [--wait-ms N] [--no-wait-exit]\n");
        return 1;
    }

    char gameExe[MAX_PATH], dllPath[MAX_PATH];
    if (!GetFullPathNameA(argv[1], MAX_PATH, gameExe, NULL)) return Fail("GetFullPathName(game)");
    if (!GetFullPathNameA(argv[2], MAX_PATH, dllPath, NULL)) return Fail("GetFullPathName(dll)");

    DWORD settleMs = 4000;
    bool waitExit = true;
    bool pluginEarly = false;
    bool noPlugin = false;   // A/B control: launch through the same path, our code absent
    char early[MAX_EARLY][MAX_PATH];
    int  earlyCount = 0;

    for (int i = 3; i < argc; ++i) {
        if (strcmp(argv[i], "--wait-ms") == 0 && i + 1 < argc) settleMs = (DWORD)atoi(argv[++i]);
        else if (strcmp(argv[i], "--no-wait-exit") == 0) waitExit = false;
        else if (strcmp(argv[i], "--early") == 0) pluginEarly = true;
        else if (strcmp(argv[i], "--no-plugin") == 0) noPlugin = true;
        else if (strcmp(argv[i], "--early-dll") == 0 && i + 1 < argc) {
            if (earlyCount >= MAX_EARLY) { fprintf(stderr, "scinject: too many --early-dll\n"); return 1; }
            if (!GetFullPathNameA(argv[++i], MAX_PATH, early[earlyCount], NULL))
                return Fail("GetFullPathName(early-dll)");
            if (GetFileAttributesA(early[earlyCount]) == INVALID_FILE_ATTRIBUTES) {
                fprintf(stderr, "scinject: early dll not found: %s\n", early[earlyCount]); return 1;
            }
            ++earlyCount;
        }
        else { fprintf(stderr, "scinject: unknown argument '%s'\n", argv[i]); return 1; }
    }

    if (GetFileAttributesA(gameExe) == INVALID_FILE_ATTRIBUTES) {
        fprintf(stderr, "scinject: game exe not found: %s\n", gameExe); return 1;
    }
    if (GetFileAttributesA(dllPath) == INVALID_FILE_ATTRIBUTES) {
        fprintf(stderr, "scinject: plugin dll not found: %s\n", dllPath); return 1;
    }

    char workDir[MAX_PATH];
    DirNameOf(gameExe, workDir, sizeof(workDir));

    STARTUPINFOA si; PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si)); si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));

    // CREATE_SUSPENDED only so we know the pid before a single instruction runs;
    // we resume immediately and inject after init. Injecting into a process whose
    // loader has never run is the fragile variant and buys us nothing here -- this
    // plugin is a passive observer, it does not need to be in before the entry point.
    if (!CreateProcessA(gameExe, NULL, NULL, NULL, FALSE, CREATE_SUSPENDED,
                        NULL, workDir, &si, &pi)) {
        return Fail("CreateProcess");
    }
    printf("scinject: launched pid=%lu  %s\n", pi.dwProcessId, gameExe);

    // --- early injection, while the process is still suspended ---------------
    for (int i = 0; i < earlyCount; ++i) {
        DWORD m = InjectDll(pi.hProcess, early[i]);
        if (m == 0) {
            fprintf(stderr, "scinject: EARLY injection FAILED for %s\n", early[i]);
            TerminateProcess(pi.hProcess, 1);
            return 5;
        }
        printf("scinject: early-injected %s -> HMODULE 0x%08lX\n", early[i], m);
    }
    if (pluginEarly && !noPlugin) {
        DWORD m = InjectDll(pi.hProcess, dllPath);
        if (m == 0) {
            fprintf(stderr, "scinject: EARLY injection FAILED for %s\n", dllPath);
            TerminateProcess(pi.hProcess, 1);
            return 5;
        }
        printf("scinject: early-injected %s -> HMODULE 0x%08lX\n", dllPath, m);
    }

    ResumeThread(pi.hThread);

    // Let the game finish its own module loading (storm.dll, ddraw.dll, ...).
    // WaitForInputIdle returns as soon as it is pumping messages; the extra
    // settle wait covers the DirectDraw setup that follows.
    DWORD wfi = WaitForInputIdle(pi.hProcess, 15000);
    printf("scinject: WaitForInputIdle -> %lu\n", wfi);
    Sleep(settleMs);

    if (WaitForSingleObject(pi.hProcess, 0) == WAIT_OBJECT_0) {
        DWORD ec = 0; GetExitCodeProcess(pi.hProcess, &ec);
        fprintf(stderr, "scinject: process exited before injection (code %lu)\n", ec);
        return 3;
    }

    if (noPlugin) {
        printf("scinject: --no-plugin, our observer was NOT injected (control run)\n");
    }
    else if (!pluginEarly) {
        DWORD remoteModule = InjectDll(pi.hProcess, dllPath);
        if (remoteModule == 0) {
            fprintf(stderr, "scinject: LoadLibraryA returned NULL in target -- DLL not loaded\n");
            return 4;
        }
        printf("scinject: injected %s -> HMODULE 0x%08lX in pid %lu\n",
               dllPath, remoteModule, pi.dwProcessId);
    }

    if (waitExit) {
        printf("scinject: waiting for game to exit (Ctrl-C to stop waiting)\n");
        WaitForSingleObject(pi.hProcess, INFINITE);
        DWORD code = 0; GetExitCodeProcess(pi.hProcess, &code);
        printf("scinject: game exited with code %lu\n", code);
    }

    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return 0;
}
