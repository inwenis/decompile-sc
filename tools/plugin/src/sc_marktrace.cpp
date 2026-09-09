// Dirty-marker trace (sc_marktrace.h).
//
// The marker 0x0041E0D0 takes its rect in registers and one stack slot:
//   EAX = x1, ECX = y1, EDX = y2, [esp+4] = x2, and cleans its own argument (ret 4).
// No C calling convention describes that, so the detour is an explicit thunk
// (the shape sc_fanout.cpp uses): save everything, hand the four values and the
// return address to a C observer, restore, jump to the trampoline. The
// trampoline replays the relocated prologue (push ebp / mov ebp,esp /
// test eax,eax) so the flags the marker's first branch reads are recomputed.
#include "sc_marktrace.h"
#include "sc_engine.h"
#include "sc_env.h"
#include "sc_hook.h"
#include "sc_log.h"

#include <string.h>

#define SC_VA_DIRTY_MARKER 0x0041E0D0u
#define SC_MARKTRACE_MAX_LINES 80000u
#define SC_MARKTRACE_CALLERS 32

static ScHook g_hk, g_hkFog, g_hkTerr, g_hkImg;
static bool g_installed = false;
static volatile LONG g_on = 0;
static unsigned g_lines = 0, g_dropped = 0, g_total = 0;
static struct { DWORD ret; unsigned n; } g_byCaller[SC_MARKTRACE_CALLERS];
static int g_callersN = 0;

extern "C" void* g_markTraceTrampoline;
void* g_markTraceTrampoline = NULL;
extern "C" void* g_fogTraceTrampoline;
void* g_fogTraceTrampoline = NULL;
extern "C" void* g_terrTraceTrampoline;
void* g_terrTraceTrampoline = NULL;
extern "C" void* g_imgTraceTrampoline;
void* g_imgTraceTrampoline = NULL;

// One line of the trace, counted per caller and capped: the cap is what keeps a
// runaway trace from becoming the stall it is meant to find.
static bool TraceLine(DWORD ret) {
    ++g_total;
    int i = 0;
    for (; i < g_callersN; ++i) if (g_byCaller[i].ret == ret) { ++g_byCaller[i].n; break; }
    if (i == g_callersN && g_callersN < SC_MARKTRACE_CALLERS) {
        g_byCaller[g_callersN].ret = ret; g_byCaller[g_callersN].n = 1; ++g_callersN;
    }
    if (g_lines >= SC_MARKTRACE_MAX_LINES) { ++g_dropped; return false; }
    ++g_lines;
    return true;
}

extern "C" void SC_GAME_ENTRY ScMarkTraceObserve(int x1, int y1, int y2, int x2, DWORD ret) {
    if (!g_on || !TraceLine(ret)) return;
    ScLog("MARK rect=(%d,%d)-(%d,%d) from=0x%08X", x1, y1, x2, y2, (unsigned)ret);
}

// The image-rect mark: ESI = a pixel rect {s32 x1, y1, x2, y2} that the function
// overwrites with cell indices, so it is read at entry.
extern "C" void SC_GAME_ENTRY ScImgMarkObserve(const int* r, DWORD ret) {
    if (!g_on || !ScReadableAt(r, 16) || !TraceLine(ret)) return;
    ScLog("IMRK rect=(%d,%d)-(%d,%d) from=0x%08X", r[0], r[1], r[2], r[3], (unsigned)ret);
}

extern "C" void ScImgTraceThunk(void);
asm(
    ".text\n"
    ".globl _ScImgTraceThunk\n"
"_ScImgTraceThunk:\n"
    "  pushal\n"                    // ESI at esp+4
    "  pushfl\n"                    // ESI at esp+8; ret at esp+36
    "  pushl 36(%esp)\n"            // ret
    "  pushl 12(%esp)\n"            // rect = saved ESI (esp moved -4)
    "  call _ScImgMarkObserve\n"
    "  addl $8, %esp\n"
    "  popfl\n"
    "  popal\n"
    "  jmp *_g_imgTraceTrampoline\n"
);

extern "C" void ScMarkTraceThunk(void);
asm(
    ".text\n"
    ".globl _ScMarkTraceThunk\n"
"_ScMarkTraceThunk:\n"
    "  pushal\n"                    // EAX at esp+28, ECX at esp+24, EDX at esp+20
    "  pushfl\n"                    // +4: EAX esp+32, ECX esp+28, EDX esp+24; ret esp+36; x2 esp+40
    "  pushl 36(%esp)\n"            // ret
    "  pushl 44(%esp)\n"            // x2   (esp moved -4)
    "  pushl 32(%esp)\n"            // y2 = saved EDX (esp moved -8)
    "  pushl 40(%esp)\n"            // y1 = saved ECX (esp moved -12)
    "  pushl 48(%esp)\n"            // x1 = saved EAX (esp moved -16)
    "  call _ScMarkTraceObserve\n"
    "  addl $20, %esp\n"
    "  popfl\n"
    "  popal\n"
    "  jmp *_g_markTraceTrampoline\n"
);


// The fog cell renderer 0x004805F0: EAX = y2, EDX = y1, [esp+4] = x1, [esp+8] = x2.
extern "C" void SC_GAME_ENTRY ScFogRenderObserve(int x1, int y1, int x2, int y2, DWORD ret) {
    if (!g_on) return;
    if (g_lines >= SC_MARKTRACE_MAX_LINES) { ++g_dropped; return; }
    ++g_lines;
    ScLog("FOGR (%d,%d)-(%d,%d) from=0x%08X", x1, y1, x2, y2, (unsigned)ret);
}
extern "C" void ScFogTraceThunk(void);
asm(
    ".text\n"
    ".globl _ScFogTraceThunk\n"
"_ScFogTraceThunk:\n"
    "  pushal\n"
    "  pushfl\n"                    // EAX esp+32, EDX esp+24; ret esp+36; x1 esp+40; x2 esp+44
    "  pushl 36(%esp)\n"            // ret
    "  pushl 36(%esp)\n"            // y2 = saved EAX (esp moved -4)
    "  pushl 52(%esp)\n"            // x2           (esp moved -8)
    "  pushl 36(%esp)\n"            // y1 = saved EDX (esp moved -12)
    "  pushl 56(%esp)\n"            // x1           (esp moved -16)
    "  call _ScFogRenderObserve\n"
    "  addl $20, %esp\n"
    "  popfl\n"
    "  popal\n"
    "  jmp *_g_fogTraceTrampoline\n"
);
// push ebp / mov ebp,esp / sub esp,0x10 -- 6 bytes, 3 whole instructions.
static const BYTE kPrologueFog[] = { 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x10 };

// The terrain run blit 0x0040C2BD: EDX = x, ECX = y, [esp+4] = width, [esp+8] = ring offset.
extern "C" void SC_GAME_ENTRY ScTerrRunObserve(int x, int y, int w, DWORD off, DWORD ret) {
    if (!g_on) return;
    if (g_lines >= SC_MARKTRACE_MAX_LINES) { ++g_dropped; return; }
    ++g_lines;
    ScLog("TERR x=%d y=%d w=%d off=%u from=0x%08X", x, y, w, (unsigned)off, (unsigned)ret);
}
extern "C" void ScTerrTraceThunk(void);
asm(
    ".text\n"
    ".globl _ScTerrTraceThunk\n"
"_ScTerrTraceThunk:\n"
    "  pushal\n"
    "  pushfl\n"                    // ECX esp+28, EDX esp+24; ret esp+36; w esp+40; off esp+44
    "  pushl 36(%esp)\n"            // ret
    "  pushl 48(%esp)\n"            // off          (esp moved -4)
    "  pushl 48(%esp)\n"            // w            (esp moved -8)
    "  pushl 40(%esp)\n"            // y = saved ECX (esp moved -12)
    "  pushl 40(%esp)\n"            // x = saved EDX (esp moved -16)
    "  call _ScTerrRunObserve\n"
    "  addl $20, %esp\n"
    "  popfl\n"
    "  popal\n"
    "  jmp *_g_terrTraceTrampoline\n"
);
// push ebp / mov ebp,esp / push ebx / push ecx -- 5 bytes, 4 whole instructions.
static const BYTE kPrologueTerr[] = { 0x55, 0x8B, 0xEC, 0x53, 0x51 };

#define SC_VA_FOG_RENDER 0x004805F0u
#define SC_VA_TERRAIN_RUN 0x0040C2BDu

// push ebp / mov ebp,esp / test eax,eax -- 5 bytes, 3 whole instructions, none PC-relative.
static const BYTE kPrologueMarker[] = { 0x55, 0x8B, 0xEC, 0x85, 0xC0 };
// push ebp / mov ebp,esp / push ecx / mov eax,[esi] -- 6 bytes, 4 whole instructions,
// none PC-relative.
static const BYTE kPrologueImg[] = { 0x55, 0x8B, 0xEC, 0x51, 0x8B, 0x06 };

bool ScMarkTraceWanted(void) { return ScEnvOptIn("SCPLUGIN_MARKTRACE"); }

void ScMarkTraceInstall(BYTE* moduleBase, bool writeAllowed) {
    ScEngineSetModuleBase(moduleBase);
    memset(&g_hk, 0, sizeof(g_hk)); memset(&g_hkFog, 0, sizeof(g_hkFog)); memset(&g_hkTerr, 0, sizeof(g_hkTerr));
    memset(&g_hkImg, 0, sizeof(g_hkImg));
    g_installed = false; g_on = 0; g_lines = g_dropped = g_total = 0; g_callersN = 0;
    if (!ScMarkTraceWanted()) return;
    if (!writeAllowed) {
        ScLog("MARKTRACE: %%SCPLUGIN_MARKTRACE%% set but the mode is observe -- IGNORED.");
        return;
    }
    if (!ScHookInstall(&g_hk, "dirtyMarker", ScRuntimeAddr(SC_VA_DIRTY_MARKER),
                       (void*)&ScMarkTraceThunk, (int)sizeof(kPrologueMarker),
                       kPrologueMarker, (int)sizeof(kPrologueMarker))) {
        ScLog("MARKTRACE: marker hook failed to install -- off");
        return;
    }
    g_markTraceTrampoline = g_hk.trampoline;
    if (ScHookInstall(&g_hkFog, "fogRender", ScRuntimeAddr(SC_VA_FOG_RENDER), (void*)&ScFogTraceThunk,
                      (int)sizeof(kPrologueFog), kPrologueFog, (int)sizeof(kPrologueFog)))
        g_fogTraceTrampoline = g_hkFog.trampoline;
    if (ScHookInstall(&g_hkTerr, "terrainRun", ScRuntimeAddr(SC_VA_TERRAIN_RUN), (void*)&ScTerrTraceThunk,
                      (int)sizeof(kPrologueTerr), kPrologueTerr, (int)sizeof(kPrologueTerr)))
        g_terrTraceTrampoline = g_hkTerr.trampoline;
    if (ScHookInstall(&g_hkImg, "imageMark", ScRuntimeAddr(SC_VA_IMAGE_MARK), (void*)&ScImgTraceThunk,
                      (int)sizeof(kPrologueImg), kPrologueImg, (int)sizeof(kPrologueImg)))
        g_imgTraceTrampoline = g_hkImg.trampoline;
    g_installed = true;
    ScLog("MARKTRACE: armed (hook at 0x%08X); a 'marktrace-on' marker starts the MARK lines, "
          "'marktrace-off' stops them and prints the per-caller totals", SC_VA_DIRTY_MARKER);
}

void ScMarkTraceRemove(void) {
    if (!g_installed) return;
    g_on = 0;
    ScHookRemove(&g_hk);
    if (g_hkFog.installed) ScHookRemove(&g_hkFog);
    if (g_hkTerr.installed) ScHookRemove(&g_hkTerr);
    if (g_hkImg.installed) ScHookRemove(&g_hkImg);
    g_installed = false;
}

void ScMarkTraceOnMarker(const char* label) {
    if (!g_installed || !label) return;
    if (strcmp(label, "marktrace-on") == 0) {
        g_lines = g_dropped = g_total = 0; g_callersN = 0;
        InterlockedExchange(&g_on, 1);
        ScLog("MARKTRACE on");
    } else if (strcmp(label, "marktrace-off") == 0) {
        InterlockedExchange(&g_on, 0);
        ScLog("MARKTRACE off: marks=%u lines=%u dropped=%u callers=%d", g_total, g_lines, g_dropped, g_callersN);
        for (int i = 0; i < g_callersN; ++i)
            ScLog("MARKTRACE caller 0x%08X marks=%u", (unsigned)g_byCaller[i].ret, g_byCaller[i].n);
    }
}

// ---------------------------------------------------------------------------
// The posted cursor: the GetCursorPos import answers from the cursor layer
// ---------------------------------------------------------------------------

static DWORD* g_cursorSlot   = NULL;   // the import slot, once installed
static DWORD  g_cursorStock  = 0;      // what the slot held before the first write
static DWORD  g_cursorSeen   = 0;      // the last foreign value the poll replaced
static unsigned g_cursorReasserts = 0;

// The cursor layer's rect (layer 0, s16 left/top at +2/+4) is written by the engine's
// own cursor path from the position the window procedure stored for the last mouse
// message, so it is the posted cursor in the coordinates the edge-scroll compares.
static BOOL WINAPI HkGetCursorPos(POINT* p) {
    if (!p) return FALSE;
    const short* r = (const short*)ScRuntimeAddr(SC_VA_GRAPHIC_LAYERS + SC_LAYER_OFF_LEFT);
    p->x = r[0];
    p->y = r[1];
    return TRUE;
}

static bool CursorSlotWrite(DWORD value) {
    DWORD old = 0;
    if (!VirtualProtect(g_cursorSlot, sizeof(DWORD), PAGE_READWRITE, &old)) return false;
    *g_cursorSlot = value;
    VirtualProtect(g_cursorSlot, sizeof(DWORD), old, &old);
    return true;
}

void ScCursorPostedInstall(BYTE* moduleBase, bool writeAllowed) {
    if (!writeAllowed || !ScEnvOptIn("SCPLUGIN_CURSOR_POSTED")) return;
    g_cursorSlot = (DWORD*)(moduleBase + (SC_VA_IMPORT_GETCURSORPOS - SC_PREFERRED_IMAGE_BASE));
    if (!ScReadableAt(g_cursorSlot, sizeof(DWORD))) { g_cursorSlot = NULL; return; }
    g_cursorStock = *g_cursorSlot;
    if (!CursorSlotWrite((DWORD)(DWORD_PTR)&HkGetCursorPos)) { g_cursorSlot = NULL; return; }
    ScLog("CURSOR posted: GetCursorPos import at 0x%08X answers from the cursor layer (was 0x%08X)",
          (unsigned)(DWORD_PTR)g_cursorSlot, (unsigned)g_cursorStock);
}

void ScCursorPostedPoll(void) {
    if (!g_cursorSlot) return;
    const DWORD cur = *g_cursorSlot;
    if (cur == (DWORD)(DWORD_PTR)&HkGetCursorPos) return;
    if (cur != g_cursorSeen) {
        ScLog("CURSOR posted: the import was rewritten to 0x%08X (a windowed helper's hook); re-asserted",
              (unsigned)cur);
        g_cursorSeen = cur;
    }
    if (CursorSlotWrite((DWORD)(DWORD_PTR)&HkGetCursorPos)) ++g_cursorReasserts;
}

void ScCursorPostedRemove(void) {
    if (!g_cursorSlot) return;
    // The helper's value, when it took the slot after us, is the one to leave behind:
    // restoring the stock import under a still-loaded cnc-ddraw would bypass its
    // translation for the rest of the process.
    CursorSlotWrite(g_cursorSeen ? g_cursorSeen : g_cursorStock);
    ScLog("CURSOR posted: import restored to 0x%08X after %u re-assert(s)",
          (unsigned)(g_cursorSeen ? g_cursorSeen : g_cursorStock), g_cursorReasserts);
    g_cursorSlot = NULL;
}
