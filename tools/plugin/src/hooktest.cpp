// hooktest.cpp -- offline unit test for the inline-detour engine in sc_hook.cpp.
//
// WHY THIS EXISTS
//   The detour engine is the one piece of task 011 that writes executable memory in
//   a foreign process. A bug in it does not produce a wrong answer, it produces a
//   corrupted game -- and the only place we can observe that is a user's single
//   hand-driven test run. So the engine is proved HERE first, in a throwaway 32-bit
//   process, against three functions whose prologues are hand-written to be
//   byte-identical in shape to the three real StarCraft functions we patch:
//
//     55 8B EC 51 A1 <abs32>   9 bytes, 4 instrs  -- queueCommand        (fastcall)
//     55 8B EC 83 EC 5C        6 bytes, 3 instrs  -- CMDACT_Select       (stdcall, RET 8)
//     55 8B EC 53 56           5 bytes, 4 instrs  -- sortOverflowHandler (EAX/ECX + stack, RET 8)
//
//   No StarCraft file is involved and the game is not launched. `build.ps1 -Test`
//   builds and runs it; a non-zero exit fails the build.

#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "sc_hook.h"
#include "sc_log.h"

static int g_failures = 0;

static void Check(const char* what, long long got, long long want) {
    if (got == want) {
        printf("  ok   %-46s = %lld\n", what, got);
    } else {
        printf("  FAIL %-46s = %lld (expected %lld)\n", what, got, want);
        ++g_failures;
    }
}

// ---------------------------------------------------------------------------
// Test targets, written in assembly so their prologues match the real ones byte
// for byte in shape (length and instruction boundaries), which is precisely what
// the patch-window constants encode.
// ---------------------------------------------------------------------------

extern "C" unsigned __attribute__((fastcall)) TgtFastcall(unsigned a, unsigned b);
extern "C" unsigned __attribute__((stdcall))  TgtStdcall(unsigned a, unsigned b);
extern "C" void TgtMixed(void);   // EAX=count, ECX=ptr, stack: unit, clicked; RET 8

extern "C" unsigned g_mixedResult;

asm(
    ".data\n"
".globl _g_testGlobal\n"
"_g_testGlobal: .long 7\n"
".globl _g_mixedResult\n"
"_g_mixedResult: .long 0\n"

    ".text\n"
    // The C declarations above are fastcall/stdcall, so the compiler emits calls to
    // the DECORATED names. Alias them onto the plain asm labels, or the linker
    // resolves them with a "stdcall fixup" warning on every build.
    ".set \"@TgtFastcall@8\", _TgtFastcall\n"
    ".globl \"@TgtFastcall@8\"\n"
    ".set \"_TgtStdcall@8\", _TgtStdcall\n"
    ".globl \"_TgtStdcall@8\"\n"

    // unsigned __fastcall TgtFastcall(ecx=a, edx=b) -> a*2 + b + g_testGlobal
    // prologue: 55 8B EC 51 A1 <abs32>   == 9 bytes / 4 instructions
".globl _TgtFastcall\n"
"_TgtFastcall:\n"
    // `55 8B EC` verbatim: GAS assembles `mov %esp,%ebp` as 89 E5, the other legal
    // encoding, and StarCraft's VC6-era build uses 8B EC. The prologue check found
    // that difference the first time this test ran -- which is exactly its job, but
    // here the point is to reproduce the game's byte shape, so pin the encoding.
    "  .byte 0x55, 0x8B, 0xEC\n"
    "  push %ecx\n"
    "  mov  _g_testGlobal, %eax\n"
    "  add  %ecx, %eax\n"
    "  add  %ecx, %eax\n"
    "  add  %edx, %eax\n"
    "  mov  %ebp, %esp\n"
    "  pop  %ebp\n"
    "  ret\n"

    // unsigned __stdcall TgtStdcall(a, b) -> a + b*3 ; RET 8
    // prologue: 55 8B EC 83 EC 5C        == 6 bytes / 3 instructions
".globl _TgtStdcall\n"
"_TgtStdcall:\n"
    // `55 8B EC` verbatim: GAS assembles `mov %esp,%ebp` as 89 E5, the other legal
    // encoding, and StarCraft's VC6-era build uses 8B EC. The prologue check found
    // that difference the first time this test ran -- which is exactly its job, but
    // here the point is to reproduce the game's byte shape, so pin the encoding.
    "  .byte 0x55, 0x8B, 0xEC\n"
    "  sub  $0x5c, %esp\n"
    "  mov  8(%ebp), %eax\n"
    "  mov  12(%ebp), %edx\n"
    "  lea  (%edx,%edx,2), %edx\n"
    "  add  %edx, %eax\n"
    "  mov  %ebp, %esp\n"
    "  pop  %ebp\n"
    "  ret  $8\n"

    // TgtMixed: EAX = count, ECX = ptr, [ebp+8] = unit, [ebp+12] = clicked.
    // Writes count + *ptr + unit + clicked into g_mixedResult. RET 8.
    // prologue: 55 8B EC 53 56           == 5 bytes / 4 instructions
".globl _TgtMixed\n"
"_TgtMixed:\n"
    // `55 8B EC` verbatim: GAS assembles `mov %esp,%ebp` as 89 E5, the other legal
    // encoding, and StarCraft's VC6-era build uses 8B EC. The prologue check found
    // that difference the first time this test ran -- which is exactly its job, but
    // here the point is to reproduce the game's byte shape, so pin the encoding.
    "  .byte 0x55, 0x8B, 0xEC\n"
    "  push %ebx\n"
    "  push %esi\n"
    "  mov  %eax, %esi\n"
    "  mov  %ecx, %ebx\n"
    "  mov  8(%ebp), %eax\n"
    "  add  %esi, %eax\n"
    "  add  (%ebx), %eax\n"
    "  add  12(%ebp), %eax\n"
    "  mov  %eax, _g_mixedResult\n"
    "  pop  %esi\n"
    "  pop  %ebx\n"
    "  pop  %ebp\n"
    "  ret  $8\n"
);

// Calls TgtMixed with the awkward convention from C.
static void CallMixed(unsigned count, unsigned* ptr, unsigned unit, unsigned clicked) {
    asm volatile(
        "pushl %[clicked]\n"
        "pushl %[unit]\n"
        "movl  %[cnt], %%eax\n"
        "movl  %[p],   %%ecx\n"
        "call  _TgtMixed\n"
        :
        : [clicked] "r"(clicked), [unit] "r"(unit), [cnt] "r"(count), [p] "r"(ptr)
        : "eax", "ecx", "edx", "memory");
}

// ---------------------------------------------------------------------------
// Detours
// ---------------------------------------------------------------------------

static ScHook g_hFast, g_hStd, g_hMixed;

static unsigned g_fastCalls = 0, g_stdCalls = 0, g_mixedCalls = 0;
static unsigned g_lastMixedCount = 0, g_lastMixedUnit = 0, g_lastMixedClicked = 0;
static unsigned g_lastMixedFirstSlot = 0;

typedef unsigned (__attribute__((fastcall)) *FastFn)(unsigned, unsigned);
typedef unsigned (__attribute__((stdcall))  *StdFn)(unsigned, unsigned);

static unsigned __attribute__((fastcall)) HkFast(unsigned a, unsigned b) {
    ++g_fastCalls;
    return ((FastFn)g_hFast.trampoline)(a, b) + 1000;
}

static unsigned __attribute__((stdcall)) HkStd(unsigned a, unsigned b) {
    ++g_stdCalls;
    return ((StdFn)g_hStd.trampoline)(a, b) + 2000;
}

extern "C" void  ScTestMixedObserve(unsigned count, unsigned* ptr, unsigned unit,
                                    unsigned clicked);
extern "C" void  ScTestMixedThunk(void);
extern "C" void* g_testMixedTrampoline;
void* g_testMixedTrampoline = NULL;

// Byte-for-byte the same thunk shape sc_fanout.cpp uses for the real overflow
// handler; testing it here is the point.
asm(
    ".text\n"
".globl _ScTestMixedThunk\n"
"_ScTestMixedThunk:\n"
    "  pushal\n"
    "  pushfl\n"
    "  pushl 44(%esp)\n"          // clicked : entry+8
    "  pushl 44(%esp)\n"          // unit    : entry+4
    "  pushl 36(%esp)\n"          // ptr     : saved ECX
    "  pushl 44(%esp)\n"          // count   : saved EAX
    "  call _ScTestMixedObserve\n"
    "  addl $16, %esp\n"
    "  popfl\n"
    "  popal\n"
    "  jmp *_g_testMixedTrampoline\n"
);

extern "C" void ScTestMixedObserve(unsigned count, unsigned* ptr, unsigned unit,
                                   unsigned clicked) {
    ++g_mixedCalls;
    g_lastMixedCount   = count;
    g_lastMixedUnit    = unit;
    g_lastMixedClicked = clicked;
    g_lastMixedFirstSlot = ptr ? ptr[0] : 0xFFFFFFFFu;
}

// ---------------------------------------------------------------------------

int main(void) {
    char tmp[MAX_PATH];
    GetTempPathA(MAX_PATH, tmp);
    lstrcatA(tmp, "scplugin-hooktest.log");
    SetEnvironmentVariableA("SCPLUGIN_LOG", tmp);
    ScLogOpen();
    printf("hooktest: log -> %s\n", tmp);

    unsigned slots[4] = { 11, 22, 33, 44 };

    printf("\n[1] baseline (unhooked)\n");
    Check("TgtFastcall(5,3) = 5*2+3+7", TgtFastcall(5, 3), 20);
    Check("TgtStdcall(5,3)  = 5+3*3",   TgtStdcall(5, 3), 14);
    CallMixed(2, slots, 100, 1000);
    Check("TgtMixed -> 2+11+100+1000", g_mixedResult, 1113);

    printf("\n[2] the signature check refuses a wrong prologue\n");
    {
        ScHook bogus;
        const BYTE wrong[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0x00 };
        bool ok = ScHookInstall(&bogus, "bogus", (void*)&TgtFastcall, (void*)&HkFast,
                                5, wrong, (int)sizeof(wrong));
        Check("install with a mismatched prologue is refused", ok ? 1 : 0, 0);
        Check("nothing was patched: TgtFastcall(5,3)", TgtFastcall(5, 3), 20);
    }

    printf("\n[3] install the three detours\n");
    {
        const BYTE pFast[]  = { 0x55, 0x8B, 0xEC, 0x51, 0xA1 };
        const BYTE pStd[]   = { 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x5C };
        const BYTE pMixed[] = { 0x55, 0x8B, 0xEC, 0x53, 0x56 };

        Check("install queueCommand-shaped (9B window)",
              ScHookInstall(&g_hFast, "fast", (void*)&TgtFastcall, (void*)&HkFast,
                            9, pFast, (int)sizeof(pFast)) ? 1 : 0, 1);
        Check("install CMDACT_Select-shaped (6B window)",
              ScHookInstall(&g_hStd, "std", (void*)&TgtStdcall, (void*)&HkStd,
                            6, pStd, (int)sizeof(pStd)) ? 1 : 0, 1);
        bool m = ScHookInstall(&g_hMixed, "mixed", (void*)&TgtMixed,
                               (void*)&ScTestMixedThunk, 5, pMixed, (int)sizeof(pMixed));
        if (m) g_testMixedTrampoline = g_hMixed.trampoline;
        Check("install sortOverflow-shaped (5B window)", m ? 1 : 0, 1);
    }

    printf("\n[4] detours run, trampolines still compute the original result\n");
    Check("TgtFastcall(5,3) -> original 20 + 1000", TgtFastcall(5, 3), 1020);
    Check("  detour entered", g_fastCalls, 1);
    Check("TgtFastcall(9,1) -> original 26 + 1000", TgtFastcall(9, 1), 1026);
    Check("TgtStdcall(5,3)  -> original 14 + 2000", TgtStdcall(5, 3), 2014);
    Check("  detour entered", g_stdCalls, 1);

    printf("\n[5] the register-convention thunk sees EAX/ECX AND the stack args,\n"
           "    and the original still runs with every register intact\n");
    g_mixedResult = 0;
    CallMixed(2, slots, 100, 1000);
    Check("observer saw count (EAX)",     g_lastMixedCount, 2);
    Check("observer saw ptr[0] (ECX)",    g_lastMixedFirstSlot, 11);
    Check("observer saw unit (stack +4)", g_lastMixedUnit, 100);
    Check("observer saw clicked (+8)",    g_lastMixedClicked, 1000);
    Check("original still produced 1113", g_mixedResult, 1113);
    Check("  thunk entered once",         g_mixedCalls, 1);

    // Stack discipline: if the thunk leaked or over-popped, a loop desyncs fast.
    g_mixedCalls = 0;
    for (int i = 0; i < 200; ++i) CallMixed(1, slots, 1, 1);
    Check("200 calls, stack stays balanced", g_mixedResult, 1 + 11 + 1 + 1);
    Check("  thunk entered 200 times",       g_mixedCalls, 200);

    printf("\n[6] removal restores the originals exactly\n");
    Check("remove fast",  ScHookRemove(&g_hFast) ? 1 : 0, 1);
    Check("remove std",   ScHookRemove(&g_hStd) ? 1 : 0, 1);
    Check("remove mixed", ScHookRemove(&g_hMixed) ? 1 : 0, 1);
    unsigned fastBefore = g_fastCalls, stdBefore = g_stdCalls, mixedBefore = g_mixedCalls;
    Check("TgtFastcall(5,3) back to 20", TgtFastcall(5, 3), 20);
    Check("TgtStdcall(5,3)  back to 14", TgtStdcall(5, 3), 14);
    g_mixedResult = 0;
    CallMixed(2, slots, 100, 1000);
    Check("TgtMixed back to 1113",       g_mixedResult, 1113);
    Check("no detour ran after removal (fast)",  g_fastCalls - fastBefore, 0);
    Check("no detour ran after removal (std)",   g_stdCalls - stdBefore, 0);
    Check("no detour ran after removal (mixed)", g_mixedCalls - mixedBefore, 0);

    printf("\nhooktest: %d failure(s)\n", g_failures);
    ScLogClose();
    return g_failures == 0 ? 0 : 1;
}
