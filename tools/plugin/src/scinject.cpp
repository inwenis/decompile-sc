// scinject.cpp -- 32-bit launcher + LoadLibrary injector for task 008.
//
// Usage:
//   scinject.exe <game-exe> <plugin-dll> [options]
//     --early-dll <path>   inject this DLL BEFORE the process is resumed
//                          (repeatable; order preserved)
//     --early              inject <plugin-dll> early too, instead of after init
//     --no-plugin          launch, but do NOT inject <plugin-dll> (A/B control)
//     --wait-ms N          settle wait after WaitForInputIdle (default 4000)
//     --no-wait-exit       return instead of waiting for the game to exit
//
// Prints "scinject: PID=<n>" on stdout so a caller can tie its own post-launch
// checks to this exact process rather than to whatever is called StarCraft.
//
// FAILURE POLICY: every exit path after CreateProcess goes through Bail(), which
// terminates the game if it is still alive and always closes both handles. A
// launch that could not deliver what was asked for must not leave a process
// behind -- least of all a suspended one holding the working copy open.
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

// What this process returns, and what each number MEANS. The values are a
// contract -- drive-game.ps1, run-with-plugin.ps1 and test-combat-death.ps1 all
// branch on the number -- so they are named here rather than renumbered.
enum ScInjectExit {
    SCINJECT_OK             = 0,
    SCINJECT_BAD_ARGS       = 1,   // usage, unknown flag, or a path that is not there
    SCINJECT_WIN32          = 2,   // a Win32 call failed; the reason is on stderr
    SCINJECT_GAME_EXITED    = 3,   // the game died on its own before injection
    SCINJECT_INJECT_FAILED  = 4,   // LoadLibraryA returned NULL inside the game
    SCINJECT_EARLY_FAILED   = 5,   // an early DLL could not be injected
    SCINJECT_RESUME_FAILED  = 6,   // ResumeThread failed; the game never started
};

// MinGW's CRT expands wildcards in argv by default. '?' is a wildcard, so
// '\\?\C:\sc-install\...' arrived at main() already mangled -- which silently
// defeated the pristine-install guard below, since it never saw the real path.
// Every argument here is a filesystem path supplied by a caller that already
// knows what it means; there is nothing to glob.
extern "C" { int _CRT_glob = 0; }

// Prints why a Win32 call failed and hands back the exit code for it. It does NOT
// terminate anything and it does NOT end the run -- five of its callers deliberately
// carry on and clean up first. (Bail(), below, is the one that ends things.)
static int ReportWin32Error(const char* what) {
    fprintf(stderr, "scinject: %s failed, GetLastError=%lu\n", what, GetLastError());
    return SCINJECT_WIN32;
}

// Runs LoadLibraryA(dllPath) on a remote thread. Returns the resulting HMODULE
// (0 on failure). Works on a suspended process too: the remote thread drives
// LdrInitializeThunk, so the loader is up by the time LoadLibraryA runs.
static DWORD InjectDll(HANDLE hProc, const char* dllPath) {
    size_t bytes = strlen(dllPath) + 1;
    LPVOID remote = VirtualAllocEx(hProc, NULL, bytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remote) { ReportWin32Error("VirtualAllocEx"); return 0; }

    SIZE_T written = 0;
    if (!WriteProcessMemory(hProc, remote, dllPath, bytes, &written) || written != bytes) {
        ReportWin32Error("WriteProcessMemory");
        VirtualFreeEx(hProc, remote, 0, MEM_RELEASE);
        return 0;
    }

    FARPROC loadLibrary = GetProcAddress(GetModuleHandleA("kernel32.dll"), "LoadLibraryA");
    if (!loadLibrary) {
        ReportWin32Error("GetProcAddress(LoadLibraryA)");
        VirtualFreeEx(hProc, remote, 0, MEM_RELEASE);
        return 0;
    }

    // LoadLibraryA's real signature (HMODULE(LPCSTR)) is call-compatible with a
    // thread start routine on x86 stdcall: one pointer argument, return in EAX.
    LPTHREAD_START_ROUTINE start = (LPTHREAD_START_ROUTINE)(void*)loadLibrary;
    HANDLE hThread = CreateRemoteThread(hProc, NULL, 0, start, remote, 0, NULL);
    if (!hThread) { ReportWin32Error("CreateRemoteThread"); VirtualFreeEx(hProc, remote, 0, MEM_RELEASE); return 0; }

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

// \\?\C:\x and \\.\C:\x name the same file as C:\x, but the ANSI path APIs do not
// understand the prefix -- GetFullPathNameA mangles such a path into nonsense.
// Strip it at argv intake so the guard, CreateProcess and the "does it exist"
// check all see one ordinary path.
static void StripDevicePrefix(const char* in, char* out, size_t outLen) {
    if (strlen(in) >= 4 && in[0] == '\\' && in[1] == '\\' &&
        (in[2] == '?' || in[2] == '.') && in[3] == '\\') {
        const char* rest = in + 4;
        if (_strnicmp(rest, "UNC\\", 4) == 0) {          // \\?\UNC\srv\share -> \\srv\share
            lstrcpynA(out, "\\\\", (int)outLen);
            lstrcpynA(out + 2, rest + 4, (int)outLen - 2);
            return;
        }
        lstrcpynA(out, rest, (int)outLen);
        return;
    }
    lstrcpynA(out, in, (int)outLen);
}

// Canonical form of a path, as far as the filesystem will tell us: absolute,
// backslashed, 8.3 components expanded. Used only by the guard below.
static void CanonicalPath(const char* in, char* out, size_t outLen) {
    char src[MAX_PATH];
    StripDevicePrefix(in, src, sizeof(src));

    char full[MAX_PATH];
    if (!GetFullPathNameA(src, MAX_PATH, full, NULL)) lstrcpynA(full, src, MAX_PATH);
    if (!GetLongPathNameA(full, out, (DWORD)outLen)) lstrcpynA(out, full, (int)outLen);

    size_t n = strlen(out);
    while (n > 3 && out[n - 1] == '\\') out[--n] = '\0';
}

// Hard rule 1 of task 008: C:\sc-install\Starcraft is the user's playable
// install and is never touched -- not even launched, which reads it. The wrapper
// script guards this too; this is the same check one layer down, so calling
// scinject.exe by hand cannot get past it.
static bool IsUnderPristineInstall(const char* path, char* canonOut, size_t canonLen) {
    static const char* kRoot = "C:\\sc-install";
    CanonicalPath(path, canonOut, canonLen);

    size_t rootLen = strlen(kRoot);
    if (_strnicmp(canonOut, kRoot, rootLen) != 0) return false;
    return canonOut[rootLen] == '\0' || canonOut[rootLen] == '\\';
}

// Single exit point for every failure after CreateProcess: never leave a game
// process behind, and never leak a handle. Terminating a still-running game is
// deliberate -- the alternative (used to be the late-injection path) was an
// unobserved process the caller had no handle on.
static int Bail(PROCESS_INFORMATION* pi, int rc) {
    if (WaitForSingleObject(pi->hProcess, 0) != WAIT_OBJECT_0) {
        TerminateProcess(pi->hProcess, 1);
        WaitForSingleObject(pi->hProcess, 5000);
    }
    CloseHandle(pi->hThread);
    CloseHandle(pi->hProcess);
    return rc;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        fprintf(stderr,
            "usage: scinject.exe <game-exe> <plugin-dll> [--early-dll <path>]... "
            "[--early] [--no-plugin] [--wait-ms N] [--no-wait-exit] [--desktop <name>]\n");
        return SCINJECT_BAD_ARGS;
    }

    char gameExe[MAX_PATH], dllPath[MAX_PATH], raw[MAX_PATH];
    StripDevicePrefix(argv[1], raw, sizeof(raw));
    if (!GetFullPathNameA(raw, MAX_PATH, gameExe, NULL)) return ReportWin32Error("GetFullPathName(game)");
    StripDevicePrefix(argv[2], raw, sizeof(raw));
    if (!GetFullPathNameA(raw, MAX_PATH, dllPath, NULL)) return ReportWin32Error("GetFullPathName(dll)");

    DWORD settleMs = 4000;
    bool waitExit = true;
    bool pluginEarly = false;
    bool noPlugin = false;   // A/B control: launch through the same path, our code absent
    char early[MAX_EARLY][MAX_PATH];
    int  earlyCount = 0;
    // task 040: name the target desktop explicitly rather than relying on
    // inheritance from the calling thread's current desktop -- measured that the
    // inheritance chain does not reliably hold through PowerShell's own
    // process-launch path. NULL (unset) keeps the default behaviour for every
    // other caller: STARTUPINFO.lpDesktop stays NULL, so CreateProcess inherits
    // the caller's desktop as it always did.
    const char* desktopName = NULL;

    for (int i = 3; i < argc; ++i) {
        if (strcmp(argv[i], "--wait-ms") == 0 && i + 1 < argc) settleMs = (DWORD)atoi(argv[++i]);
        else if (strcmp(argv[i], "--no-wait-exit") == 0) waitExit = false;
        else if (strcmp(argv[i], "--early") == 0) pluginEarly = true;
        else if (strcmp(argv[i], "--no-plugin") == 0) noPlugin = true;
        else if (strcmp(argv[i], "--desktop") == 0 && i + 1 < argc) desktopName = argv[++i];
        else if (strcmp(argv[i], "--early-dll") == 0 && i + 1 < argc) {
            if (earlyCount >= MAX_EARLY) { fprintf(stderr, "scinject: too many --early-dll\n"); return SCINJECT_BAD_ARGS; }
            StripDevicePrefix(argv[++i], raw, sizeof(raw));
            if (!GetFullPathNameA(raw, MAX_PATH, early[earlyCount], NULL))
                return ReportWin32Error("GetFullPathName(early-dll)");
            if (GetFileAttributesA(early[earlyCount]) == INVALID_FILE_ATTRIBUTES) {
                fprintf(stderr, "scinject: early dll not found: %s\n", early[earlyCount]); return SCINJECT_BAD_ARGS;
            }
            ++earlyCount;
        }
        else { fprintf(stderr, "scinject: unknown argument '%s'\n", argv[i]); return SCINJECT_BAD_ARGS; }
    }

    char gameCanon[MAX_PATH];
    if (IsUnderPristineInstall(gameExe, gameCanon, sizeof(gameCanon))) {
        fprintf(stderr, "scinject: refusing to launch from the pristine install.\n"
                        "          '%s' resolves to '%s'.\n"
                        "          Use the working copy (C:\\sc-work\\1161-base).\n",
                argv[1], gameCanon);
        return SCINJECT_BAD_ARGS;
    }

    if (GetFileAttributesA(gameExe) == INVALID_FILE_ATTRIBUTES) {
        fprintf(stderr, "scinject: game exe not found: %s\n", gameExe); return SCINJECT_BAD_ARGS;
    }
    if (GetFileAttributesA(dllPath) == INVALID_FILE_ATTRIBUTES) {
        fprintf(stderr, "scinject: plugin dll not found: %s\n", dllPath); return SCINJECT_BAD_ARGS;
    }

    char workDir[MAX_PATH];
    DirNameOf(gameExe, workDir, sizeof(workDir));

    STARTUPINFOA si; PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si)); si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));
    if (desktopName) si.lpDesktop = (char*)desktopName;

    // CREATE_SUSPENDED always, for two reasons: the pid is known before a single
    // instruction runs, and it is the window in which --early-dll injection has
    // to happen (see the header -- the windowed-mode helper must hook before
    // DirectDraw initialises). With no early DLLs the process is resumed straight
    // away and the plugin goes in after init instead.
    if (!CreateProcessA(gameExe, NULL, NULL, NULL, FALSE, CREATE_SUSPENDED,
                        NULL, workDir, &si, &pi)) {
        return ReportWin32Error("CreateProcess");
    }
    printf("scinject: launched pid=%lu  %s\n", pi.dwProcessId, gameExe);
    printf("scinject: PID=%lu\n", pi.dwProcessId);   // machine-readable, for callers
    fflush(stdout);

    // --- early injection, while the process is still suspended ---------------
    for (int i = 0; i < earlyCount; ++i) {
        DWORD m = InjectDll(pi.hProcess, early[i]);
        if (m == 0) {
            fprintf(stderr, "scinject: EARLY injection FAILED for %s\n", early[i]);
            return Bail(&pi, SCINJECT_EARLY_FAILED);
        }
        printf("scinject: early-injected %s -> HMODULE 0x%08lX\n", early[i], m);
    }
    if (pluginEarly && !noPlugin) {
        DWORD m = InjectDll(pi.hProcess, dllPath);
        if (m == 0) {
            fprintf(stderr, "scinject: EARLY injection FAILED for %s\n", dllPath);
            return Bail(&pi, SCINJECT_EARLY_FAILED);
        }
        printf("scinject: early-injected %s -> HMODULE 0x%08lX\n", dllPath, m);
    }

    // An unchecked ResumeThread leaves the game suspended forever, holding the
    // working copy open, with a zero exit code saying everything is fine.
    if (ResumeThread(pi.hThread) == (DWORD)-1) {
        ReportWin32Error("ResumeThread");
        return Bail(&pi, SCINJECT_RESUME_FAILED);
    }

    // Let the game finish its own module loading (storm.dll, ddraw.dll, ...).
    // WaitForInputIdle returns as soon as it is pumping messages; the extra
    // settle wait covers the DirectDraw setup that follows.
    DWORD wfi = WaitForInputIdle(pi.hProcess, 15000);
    printf("scinject: WaitForInputIdle -> %lu\n", wfi);
    Sleep(settleMs);

    if (WaitForSingleObject(pi.hProcess, 0) == WAIT_OBJECT_0) {
        DWORD ec = 0; GetExitCodeProcess(pi.hProcess, &ec);
        fprintf(stderr, "scinject: process exited before injection (code %lu)\n", ec);
        return Bail(&pi, SCINJECT_GAME_EXITED);   // Bail is here for the handles
    }

    if (noPlugin) {
        printf("scinject: --no-plugin, our observer was NOT injected (control run)\n");
    }
    else if (!pluginEarly) {
        DWORD remoteModule = InjectDll(pi.hProcess, dllPath);
        if (remoteModule == 0) {
            fprintf(stderr, "scinject: LoadLibraryA returned NULL in target -- DLL not loaded\n");
            fprintf(stderr, "scinject: terminating the game rather than leaving it running unobserved\n");
            return Bail(&pi, SCINJECT_INJECT_FAILED);
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
    return SCINJECT_OK;
}
