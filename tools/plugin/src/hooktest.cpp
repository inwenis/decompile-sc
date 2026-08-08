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

#include "sc_addresses.h"
#include "sc_circles.h"
#include "sc_fanout.h"
#include "sc_hook.h"
#include "sc_hudrow.h"
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
// [7] The fan-out core, driven with no game and no hooks.
//
// A fake 3 MB "module image" is allocated so that every static VA the core touches
// (the unit array at 0x0059CCA8, the turn-buffer counters at 0x00654AA0 /
// 0x0057F0D8) resolves inside it. Units are synthesised at the real 336-byte stride
// with real uniqueness bytes, the three core entry points are called in the order
// the engine calls them, and the EXACT bytes the core would have queued are
// captured and asserted.
//
// This proves everything about stage C except whether the engine obeys the
// commands -- which is the one thing only a human at the keyboard can show.
// ---------------------------------------------------------------------------

#define FAKE_IMAGE_BYTES 0x00300000u   // covers 0x00400000 .. 0x00700000

static BYTE* g_fake = NULL;
static BYTE  g_capture[4096];
static int   g_captureLen = 0;
static int   g_captureCount = 0;

static void* FakeRt(DWORD staticVa) { return g_fake + (staticVa - SC_PREFERRED_IMAGE_BASE); }

static void __attribute__((fastcall)) CaptureEmit(const void* buf, unsigned len) {
    if (g_captureLen + (int)len > (int)sizeof(g_capture)) return;
    memcpy(g_capture + g_captureLen, buf, len);
    g_captureLen += (int)len;
    ++g_captureCount;
}

// Unit i lives at unitArray + i*336; its wire tag is (uniqueness << 11) | (i + 1).
static DWORD FakeUnit(int i) { return (DWORD)FakeRt(SC_VA_UNIT_ARRAY_BASE) + (DWORD)i * SC_CUNIT_SIZE; }
static WORD  ExpectTag(int i) {
    BYTE uniq = *(BYTE*)(FakeUnit(i) + SC_CUNIT_OFF_UNIQUENESS);
    return (WORD)(((WORD)uniq << 11) | (WORD)(i + 1));
}

static void MakeUnits(int n, BYTE player) {
    for (int i = 0; i < n; ++i) {
        BYTE* u = (BYTE*)FakeUnit(i);
        u[SC_CUNIT_OFF_UNIQUENESS] = (BYTE)(1 + (i % 7));   // varied, so a wrong
        u[SC_CUNIT_OFF_PLAYER]     = player;                // index shows up as a
    }                                                       // wrong tag
}

static void ResetQueueCounters(void) {
    *(DWORD*)FakeRt(SC_VA_BYTES_IN_CMD_QUEUE)  = 0;
    *(DWORD*)FakeRt(SC_VA_MAX_CMD_QUEUE_BYTES) = 512;
}

// Drives one whole selection: 12 visible + `overflow` beyond the cap, exactly as
// SortAllUnits + sortOverflowHandler + CMDACT_Select would.
static void DriveSelection(int total) {
    DWORD visible[SC_SELECTION_SLOTS];
    for (int i = 0; i < SC_SELECTION_SLOTS; ++i) visible[i] = FakeUnit(i);
    for (int i = SC_SELECTION_SLOTS; i < total; ++i) {
        ScFanoutOnOverflow(SC_SELECTION_SLOTS, visible, FakeUnit(i));
    }
    ScFanoutOnSelect(SC_SELECTION_SLOTS, visible);
}

// The 10-byte Right Click command the engine builds (research/command-path.md 5).
static const BYTE kRightClick[10] = { 0x14, 0x34, 0x12, 0x78, 0x56, 0, 0, 0, 0, 0 };

static int ExpectSelectAt(const char* what, int off, const int* idx, int n) {
    bool ok = (off + 2 + n * 2 <= g_captureLen) &&
              g_capture[off] == SC_CMD_SELECT && g_capture[off + 1] == (BYTE)n;
    if (ok) {
        for (int i = 0; i < n; ++i) {
            WORD got  = (WORD)(g_capture[off + 2 + i * 2] | (g_capture[off + 3 + i * 2] << 8));
            if (got != ExpectTag(idx[i])) { ok = false; break; }
        }
    }
    Check(what, ok ? 1 : 0, 1);
    return off + 2 + n * 2;
}

static int ExpectOrderAt(const char* what, int off) {
    bool ok = (off + (int)sizeof(kRightClick) <= g_captureLen) &&
              memcmp(g_capture + off, kRightClick, sizeof(kRightClick)) == 0;
    Check(what, ok ? 1 : 0, 1);
    return off + (int)sizeof(kRightClick);
}

static void FanoutCoreTests(void) {
    printf("\n[7] the fan-out core: 36 units, one right-click, no game, no hooks\n");

    g_fake = (BYTE*)VirtualAlloc(NULL, FAKE_IMAGE_BYTES, MEM_COMMIT | MEM_RESERVE,
                                 PAGE_READWRITE);
    if (!g_fake) { printf("  FAIL could not allocate the fake image\n"); ++g_failures; return; }

    MakeUnits(64, 1);
    ResetQueueCounters();
    ScFanoutTestBegin(g_fake, &CaptureEmit, 200);

    DriveSelection(36);
    g_captureLen = 0; g_captureCount = 0;
    bool suppressed = ScFanoutOnCommand(kRightClick, sizeof(kRightClick));

    Check("the engine's own order is suppressed", suppressed ? 1 : 0, 1);
    Check("commands queued = 3 pairs x (Select + order)", g_captureCount, 6);
    // 3 x (2 + 12*2) + 3 x 10 = 78 + 30 = 108
    Check("bytes queued", g_captureLen, 108);

    // Overflow chunks first, in capture order; the VISIBLE chunk last, so the
    // simulation is left holding exactly what the player can see.
    int a[SC_SELECTION_SLOTS], b[SC_SELECTION_SLOTS], v[SC_SELECTION_SLOTS];
    for (int i = 0; i < SC_SELECTION_SLOTS; ++i) { a[i] = 12 + i; b[i] = 24 + i; v[i] = i; }
    int off = 0;
    off = ExpectSelectAt("pair 1 selects units 13-24 with correct tags", off, a, 12);
    off = ExpectOrderAt ("pair 1 carries the order verbatim", off);
    off = ExpectSelectAt("pair 2 selects units 25-36", off, b, 12);
    off = ExpectOrderAt ("pair 2 carries the order verbatim", off);
    off = ExpectSelectAt("pair 3 selects the VISIBLE 12 (last)", off, v, 12);
    (void)ExpectOrderAt ("pair 3 carries the order verbatim", off);

    printf("\n    a 12-unit selection is left alone entirely\n");
    ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
    ResetQueueCounters();
    {
        DWORD visible[SC_SELECTION_SLOTS];
        for (int i = 0; i < SC_SELECTION_SLOTS; ++i) visible[i] = FakeUnit(i);
        ScFanoutOnSelect(SC_SELECTION_SLOTS, visible);
    }
    g_captureLen = 0; g_captureCount = 0;
    Check("not suppressed", ScFanoutOnCommand(kRightClick, sizeof(kRightClick)) ? 1 : 0, 0);
    Check("nothing emitted", g_captureCount, 0);

    printf("\n    a command that is not in the fan-out set passes through\n");
    ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
    ResetQueueCounters();
    DriveSelection(36);
    g_captureLen = 0; g_captureCount = 0;
    {
        const BYTE build[8] = { 0x0C, 1, 2, 3, 4, 5, 6, 7 };
        Check("0x0C not suppressed", ScFanoutOnCommand(build, sizeof(build)) ? 1 : 0, 0);
        Check("nothing emitted", g_captureCount, 0);
    }

    printf("\n    units that died between capture and order are dropped\n");
    ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
    ResetQueueCounters();
    DriveSelection(36);
    // "Kill" three of the overflow units by bumping their uniqueness byte, exactly
    // the way the engine's own stale-tag test detects a recycled slot.
    for (int i = 12; i < 15; ++i) *(BYTE*)(FakeUnit(i) + SC_CUNIT_OFF_UNIQUENESS) += 1;
    g_captureLen = 0; g_captureCount = 0;
    ScFanoutOnCommand(kRightClick, sizeof(kRightClick));
    Check("still 3 pairs", g_captureCount, 6);
    Check("first Select carries 9 units, not 12", g_capture[1], 9);
    Check("bytes queued drops by 3 tags (6B)", g_captureLen, 102);
    for (int i = 12; i < 15; ++i) *(BYTE*)(FakeUnit(i) + SC_CUNIT_OFF_UNIQUENESS) -= 1;

    printf("\n    a budget too small to hold every pair spills to the next command\n");
    ScFanoutTestBegin(g_fake, &CaptureEmit, 40);   // one pair (36B) fits, two do not
    ResetQueueCounters();
    DriveSelection(36);
    g_captureLen = 0; g_captureCount = 0;
    ScFanoutOnCommand(kRightClick, sizeof(kRightClick));
    Check("only 1 pair this turn", g_captureCount, 2);
    g_captureLen = 0; g_captureCount = 0;
    ScFanoutOnCommand(kRightClick, sizeof(kRightClick));   // next command drains more
    Check("the next command drains the rest", g_captureCount >= 2 ? 1 : 0, 1);

    printf("\n    a full turn buffer never silently eats the order\n");
    ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
    ResetQueueCounters();
    DriveSelection(36);
    *(DWORD*)FakeRt(SC_VA_BYTES_IN_CMD_QUEUE) = 510;   // no room at all
    g_captureLen = 0; g_captureCount = 0;
    Check("not suppressed, so the engine's own order still goes out",
          ScFanoutOnCommand(kRightClick, sizeof(kRightClick)) ? 1 : 0, 0);
    Check("nothing half-emitted", g_captureCount, 0);

    ScFanoutTestBegin(NULL, NULL, 200);   // leave the core inert
    VirtualFree(g_fake, 0, MEM_RELEASE);
    g_fake = NULL;
}

// ---------------------------------------------------------------------------
// [9] The per-opcode fan-out policy (task 015), driven the same way as [7].
//
// [7] proves the chunking machinery with one 10-byte right-click. This part proves the
// POLICY that decides which commands go through that machinery at all: the untargeted
// orders a player issues to a group -- Stop, Hold Position, an ability -- reach every
// unit, and the commands that must never be replayed do not, whatever the selection size.
//
// Every id used below is a row in research/data/command-opcodes.tsv, and the two named
// ones were named by pressing their key in a live game and reading the id the plugin
// logged (research/command-opcodes.md 4).
// ---------------------------------------------------------------------------

static int ExpectBytesAt(const char* what, int off, const BYTE* want, int n) {
    bool ok = (off + n <= g_captureLen) && memcmp(g_capture + off, want, (size_t)n) == 0;
    Check(what, ok ? 1 : 0, 1);
    return off + n;
}

// Runs one command against a 36-unit shadow list and reports what came out.
struct FanoutOutcome { bool suppressed; int commands; int bytes; };

static FanoutOutcome RunOne(const BYTE* cmd, int len) {
    ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
    ResetQueueCounters();
    DriveSelection(36);
    g_captureLen = 0; g_captureCount = 0;
    FanoutOutcome o;
    o.suppressed = ScFanoutOnCommand(cmd, (unsigned)len);
    o.commands = g_captureCount;
    o.bytes = g_captureLen;
    return o;
}

static void OpcodePolicyTests(void) {
    printf("\n[9] the per-opcode policy: which commands reach all 36 units\n");

    g_fake = (BYTE*)VirtualAlloc(NULL, FAKE_IMAGE_BYTES, MEM_COMMIT | MEM_RESERVE,
                                 PAGE_READWRITE);
    if (!g_fake) { printf("  FAIL could not allocate the fake image\n"); ++g_failures; return; }
    MakeUnits(64, 1);

    // --- Stop: 2 bytes, id + queued. The user's ask, in one line of assertions.
    printf("\n    Stop (0x1A) reaches all 36: 3 Select+order pairs, exact bytes\n");
    {
        const BYTE stop[2] = { 0x1A, 0x00 };
        FanoutOutcome o = RunOne(stop, sizeof(stop));
        Check("the engine's own Stop is suppressed", o.suppressed ? 1 : 0, 1);
        Check("3 pairs x (Select + Stop)", o.commands, 6);
        // 3 x (2 + 12*2) + 3 x 2 = 78 + 6 = 84
        Check("bytes queued", o.bytes, 84);

        int a[SC_SELECTION_SLOTS], b[SC_SELECTION_SLOTS], v[SC_SELECTION_SLOTS];
        for (int i = 0; i < SC_SELECTION_SLOTS; ++i) { a[i] = 12 + i; b[i] = 24 + i; v[i] = i; }
        int off = 0;
        off = ExpectSelectAt("pair 1 selects units 13-24", off, a, 12);
        off = ExpectBytesAt ("pair 1 carries Stop verbatim", off, stop, 2);
        off = ExpectSelectAt("pair 2 selects units 25-36", off, b, 12);
        off = ExpectBytesAt ("pair 2 carries Stop verbatim", off, stop, 2);
        off = ExpectSelectAt("pair 3 selects the VISIBLE 12 (last)", off, v, 12);
        (void)ExpectBytesAt ("pair 3 carries Stop verbatim", off, stop, 2);
    }

    // --- Hold Position, and the queued (shift) flag it carries.
    printf("\n    Hold Position (0x2B) reaches all 36, queued flag preserved per chunk\n");
    {
        const BYTE holdQueued[2] = { 0x2B, 0x01 };   // shift held
        FanoutOutcome o = RunOne(holdQueued, sizeof(holdQueued));
        Check("suppressed", o.suppressed ? 1 : 0, 1);
        Check("3 pairs", o.commands, 6);
        Check("bytes queued", o.bytes, 84);
        // Each chunk gets the order ONCE, with the player's own queued byte untouched,
        // so every unit ends up with exactly one queued order -- the same thing the
        // engine would have done to twelve of them.
        int off = 2 + 12 * 2;
        off = ExpectBytesAt("chunk 1 keeps queued=1", off, holdQueued, 2);
        off += 2 + 12 * 2;
        off = ExpectBytesAt("chunk 2 keeps queued=1", off, holdQueued, 2);
        off += 2 + 12 * 2;
        (void)ExpectBytesAt("chunk 3 keeps queued=1", off, holdQueued, 2);
    }

    // --- A 1-byte untargeted ability. 0x2A is the shortest command in the fan-out set,
    // so it is also the check that a length-1 order chunks correctly.
    printf("\n    a 1-byte untargeted ability (0x2A) reaches all 36\n");
    {
        const BYTE ability[1] = { 0x2A };
        FanoutOutcome o = RunOne(ability, sizeof(ability));
        Check("suppressed", o.suppressed ? 1 : 0, 1);
        Check("3 pairs", o.commands, 6);
        Check("bytes queued", o.bytes, 78 + 3);
    }

    // --- The passthrough set. These are the commands the task exists to NOT duplicate.
    printf("\n    production, cancel and research are NOT duplicated, at any selection size\n");
    {
        struct { const char* what; BYTE bytes[8]; int len; } kMustPassThrough[] = {
            { "0x1F (single-gated, spends resources through 0x00467250)", { 0x1F, 0x00, 0x00 }, 3 },
            { "0x23 (loops, but spends resources through 0x00467250)",    { 0x23, 0x67, 0x00 }, 3 },
            { "0x27 (loops, but spends resources through 0x00467250)",    { 0x27 }, 1 },
            { "0x35 (single-gated, spends resources through 0x00467250)", { 0x35, 0x00, 0x00 }, 3 },
            { "0x18 (single-gated cancel, refunds through 0x00468280)",   { 0x18 }, 1 },
            { "0x19 (loops, but refunds through 0x00468280)",             { 0x19 }, 1 },
            { "0x20 (single-gated)",                                      { 0x20, 0xFE, 0xFF }, 3 },
            { "0x0C (single-gated Build)",                                { 0x0C, 1, 2, 3, 4, 5, 6, 7 }, 8 },
            { "0x13 (control group, rebuilds the selection elsewhere)",   { 0x13, 0x01, 0x00 }, 3 },
            { "0x09 (Select itself)",                                     { 0x09, 0x01, 0x11, 0x22 }, 4 },
        };
        for (unsigned i = 0; i < sizeof(kMustPassThrough) / sizeof(kMustPassThrough[0]); ++i) {
            FanoutOutcome o = RunOne(kMustPassThrough[i].bytes, kMustPassThrough[i].len);
            char msg[160];
            _snprintf(msg, sizeof(msg), "%s: not suppressed", kMustPassThrough[i].what);
            Check(msg, o.suppressed ? 1 : 0, 0);
            _snprintf(msg, sizeof(msg), "%s: nothing emitted", kMustPassThrough[i].what);
            Check(msg, o.commands, 0);
        }
    }

    // --- The length guard. A fan-out id carrying a length the engine's dispatcher does
    // not consume for it is not that command; replaying it would hand the receive loop a
    // byte count it did not expect and desynchronise the rest of the turn buffer.
    printf("\n    a fan-out id with the wrong length is refused, not replayed\n");
    {
        const BYTE stopTooLong[3] = { 0x1A, 0x00, 0x00 };
        FanoutOutcome o = RunOne(stopTooLong, sizeof(stopTooLong));
        Check("0x1A at len=3 is not suppressed", o.suppressed ? 1 : 0, 0);
        Check("nothing emitted", o.commands, 0);

        const BYTE rightClickTooShort[4] = { 0x14, 1, 2, 3 };
        o = RunOne(rightClickTooShort, sizeof(rightClickTooShort));
        Check("0x14 at len=4 is not suppressed", o.suppressed ? 1 : 0, 0);
        Check("nothing emitted", o.commands, 0);

        const BYTE unknownId[2] = { 0x77, 0x00 };
        o = RunOne(unknownId, sizeof(unknownId));
        Check("an id the dispatcher does not accept is not suppressed", o.suppressed ? 1 : 0, 0);
        Check("nothing emitted", o.commands, 0);
    }

    // --- The set itself. Transcribing a policy table into C is exactly the sort of edit
    // that silently gains or loses an id, so the whole set is asserted, not spot-checked.
    printf("\n    the default fan-out set is exactly the 19 ids the policy table marks fanout\n");
    {
        static const BYTE kExpected[] = {
            0x14, 0x15, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x21, 0x22, 0x25,
            0x26, 0x28, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x36, 0x5A,
        };
        // Every expected id, at ITS OWN dispatcher length, must fan out.
        static const BYTE kLen[] = { 10, 11, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 1, 1, 1 };
        int fannedOut = 0;
        for (unsigned i = 0; i < sizeof(kExpected); ++i) {
            BYTE cmd[16];
            memset(cmd, 0, sizeof(cmd));
            cmd[0] = kExpected[i];
            FanoutOutcome o = RunOne(cmd, kLen[i]);
            if (o.suppressed && o.commands == 6) ++fannedOut;
            else printf("       0x%02X did NOT fan out (suppressed=%d commands=%d)\n",
                        kExpected[i], o.suppressed ? 1 : 0, o.commands);
        }
        Check("all 19 fan out at their own length", fannedOut, 19);

        // And nothing else does. ALL 39 other ids the dispatcher accepts must pass through
        // -- including the five whose length the dispatcher computes rather than reads from
        // an immediate (0x06, 0x07, 0x09, 0x0A, 0x0B). Those five carry `len = -1` in the
        // opcode table, so the length guard refuses them at any length; the arbitrary
        // lengths below are exactly the point.
        static const BYTE kOther[] = {
            0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
            0x11, 0x12, 0x13, 0x18, 0x19, 0x1F, 0x20, 0x23, 0x27, 0x29, 0x2F, 0x30,
            0x31, 0x32, 0x33, 0x34, 0x35, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x55, 0x56,
            0x57, 0x58, 0x5C,
        };
        static const BYTE kOtherLen[] = {
            1, 8, 8, 1, 4, 4, 4, 8, 3, 5, 2, 1,
            1, 5, 3, 1, 1, 3, 3, 3, 1, 3, 5, 2,
            1, 2, 1, 1, 3, 7, 1, 1, 2, 2, 2, 10,
            2, 5, 82,
        };
        int passed = 0;
        for (unsigned i = 0; i < sizeof(kOther); ++i) {
            BYTE cmd[96];
            memset(cmd, 0, sizeof(cmd));
            cmd[0] = kOther[i];
            FanoutOutcome o = RunOne(cmd, kOtherLen[i]);
            if (!o.suppressed && o.commands == 0) ++passed;
            else printf("       0x%02X was NOT passed through (suppressed=%d commands=%d)\n",
                        kOther[i], o.suppressed ? 1 : 0, o.commands);
        }
        Check("all 39 other accepted opcodes pass through untouched",
              passed, (int)sizeof(kOther));
    }

    ScFanoutTestBegin(NULL, NULL, 200);
    VirtualFree(g_fake, 0, MEM_RELEASE);
    g_fake = NULL;
}

// ---------------------------------------------------------------------------
// [8] The selection circles, driven with fake sprites and fake engine primitives.
//
// sc_circles reaches the engine through two function pointers precisely so this can
// run: the attach/detach state machine, the staleness rules and -- the point of the
// whole design -- the promise that neither sprite flag 0x08 nor CSprite::selectionIndex
// is ever written, are all asserted here with no StarCraft in the process.
//
// What is NOT provable offline is whether the engine DRAWS the image it was asked to
// attach. That is the one thing the in-game run exists to answer.
// ---------------------------------------------------------------------------

#define FAKE_SPRITE_VA 0x00680000u          // inside the fake image, clear of everything else

static DWORD g_addCalls = 0, g_removeCalls = 0;
static DWORD g_lastAddSprite = 0, g_lastAddColour = 0, g_lastAddImageId = 0;
static DWORD g_removedSprites[64];
static int   g_removedCount = 0;
static bool  g_addFails = false;            // simulate an exhausted image free list

static DWORD FakeSprite(int i) { return (DWORD)FakeRt(FAKE_SPRITE_VA) + (DWORD)i * 0x24u; }

static DWORD FakeAddCircle(DWORD sprite, DWORD colour, DWORD baseImageId) {
    ++g_addCalls;
    g_lastAddSprite = sprite; g_lastAddColour = colour; g_lastAddImageId = baseImageId;
    if (g_addFails) return 0;
    return 0xC0FFEE00u;   // a non-NULL "CImage*"; the module only tests it for zero
}

// Emulates 0x004975D0 faithfully enough to catch a double-free: it clears flag 0x01,
// and it does nothing at all when that flag is already clear.
static BYTE FakeRemoveCircle(DWORD sprite) {
    ++g_removeCalls;
    if (g_removedCount < (int)(sizeof(g_removedSprites) / sizeof(g_removedSprites[0]))) {
        g_removedSprites[g_removedCount++] = sprite;
    }
    BYTE* flags = (BYTE*)(sprite + SC_CSPRITE_OFF_FLAGS);
    if ((*flags & SC_SPRITE_FLAG_SEL_CIRCLE) == 0) return 0;
    *flags = (BYTE)(*flags & ~SC_SPRITE_FLAG_SEL_CIRCLE);
    return 1;
}

// Unit i gets sprite i, with the sprite zeroed and selectionIndex poisoned to 0xEE so
// that "nobody wrote it" is distinguishable from "somebody wrote 0".
static void MakeSprites(int n) {
    for (int i = 0; i < n; ++i) {
        DWORD s = FakeSprite(i);
        memset((void*)s, 0, 0x24);
        *(BYTE*)(s + SC_CSPRITE_OFF_SELECTION_INDEX) = 0xEE;
        *(DWORD*)(FakeUnit(i) + SC_CUNIT_OFF_SPRITE) = s;
    }
}

static ScCircleUnit CircleFor(int i) {
    ScCircleUnit c;
    c.unit       = FakeUnit(i);
    c.sprite     = 0;
    c.uniqueness = *(BYTE*)(FakeUnit(i) + SC_CUNIT_OFF_UNIQUENESS);
    c.player     = *(BYTE*)(FakeUnit(i) + SC_CUNIT_OFF_PLAYER);
    return c;
}

static void ResetCircleCounters(void) {
    g_addCalls = g_removeCalls = 0;
    g_removedCount = 0;
    g_addFails = false;
}

static bool NoSpriteWasMarkedSelected(int n) {
    for (int i = 0; i < n; ++i) {
        if (*(BYTE*)(FakeSprite(i) + SC_CSPRITE_OFF_FLAGS) & SC_SPRITE_FLAG_SELECTED) return false;
    }
    return true;
}

static bool NoSelectionIndexWasWritten(int n) {
    for (int i = 0; i < n; ++i) {
        if (*(BYTE*)(FakeSprite(i) + SC_CSPRITE_OFF_SELECTION_INDEX) != 0xEE) return false;
    }
    return true;
}

static void CircleTests(void) {
    printf("\n[8] selection circles: fake sprites, fake engine primitives\n");

    g_fake = (BYTE*)VirtualAlloc(NULL, FAKE_IMAGE_BYTES, MEM_COMMIT | MEM_RESERVE,
                                 PAGE_READWRITE);
    if (!g_fake) { printf("  FAIL could not allocate the fake image\n"); ++g_failures; return; }

    MakeUnits(64, 1);
    MakeSprites(64);
    // The colour table the module reads, BYTE[0x00581D6A + player]; player 1 -> 0x5A.
    *(BYTE*)((DWORD)FakeRt(SC_VA_SELECTION_COLOR_TABLE) + 1) = 0x5A;

    ScCirclesTestBegin(g_fake, &FakeAddCircle, &FakeRemoveCircle);
    ResetCircleCounters();

    printf("\n    attaching to three units\n");
    {
        ScCircleUnit set[3] = { CircleFor(20), CircleFor(21), CircleFor(22) };
        ScCirclesShow(set, 3);
        Check("three attach calls", (long long)g_addCalls, 3);
        Check("module holds three", ScCirclesCount(), 3);
        Check("flag 0x01 set on unit 20's sprite",
              *(BYTE*)(FakeSprite(20) + SC_CSPRITE_OFF_FLAGS) & SC_SPRITE_FLAG_SEL_CIRCLE, 1);
        Check("the colour byte came from the player table", (long long)g_lastAddColour, 0x5A);
        Check("the base image id is 0x231", (long long)g_lastAddImageId,
              SC_SELECTION_CIRCLE_IMAGE_BASE);
    }

    printf("\n    THE INVARIANT: flag 0x08 and selectionIndex are never written\n");
    Check("no sprite was marked selected", NoSpriteWasMarkedSelected(64) ? 1 : 0, 1);
    Check("no selectionIndex was written", NoSelectionIndexWasWritten(64) ? 1 : 0, 1);

    printf("\n    re-stating the set detaches the old one first\n");
    ResetCircleCounters();
    {
        ScCircleUnit set[2] = { CircleFor(30), CircleFor(31) };
        ScCirclesShow(set, 2);
        Check("three detach calls", (long long)g_removeCalls, 3);
        Check("two attach calls", (long long)g_addCalls, 2);
        Check("module holds two", ScCirclesCount(), 2);
        Check("unit 20's sprite is clean again",
              *(BYTE*)(FakeSprite(20) + SC_CSPRITE_OFF_FLAGS), 0);
    }

    printf("\n    hide takes everything off and is idempotent\n");
    ResetCircleCounters();
    ScCirclesHide();
    Check("two detach calls", (long long)g_removeCalls, 2);
    Check("module holds none", ScCirclesCount(), 0);
    ScCirclesHide();
    Check("a second hide calls nothing", (long long)g_removeCalls, 2);

    printf("\n    a sprite the ENGINE owns is never touched\n");
    ResetCircleCounters();
    {
        // flag 0x08: the engine has this unit in its 12. flag 0x01 alone: something
        // else already put a circle on it. Adopting either would mean freeing an
        // image we did not allocate.
        *(BYTE*)(FakeSprite(40) + SC_CSPRITE_OFF_FLAGS) = SC_SPRITE_FLAG_SELECTED;
        *(BYTE*)(FakeSprite(41) + SC_CSPRITE_OFF_FLAGS) = SC_SPRITE_FLAG_SEL_CIRCLE;
        ScCircleUnit set[3] = { CircleFor(40), CircleFor(41), CircleFor(42) };
        ScCirclesShow(set, 3);
        Check("only the free unit was attached", (long long)g_addCalls, 1);
        Check("module holds one", ScCirclesCount(), 1);
        ResetCircleCounters();
        ScCirclesHide();
        Check("and only that one is detached", (long long)g_removeCalls, 1);
        Check("  it was unit 42's sprite", (long long)g_removedSprites[0], FakeSprite(42));
        *(BYTE*)(FakeSprite(40) + SC_CSPRITE_OFF_FLAGS) = 0;
        *(BYTE*)(FakeSprite(41) + SC_CSPRITE_OFF_FLAGS) = 0;
    }

    printf("\n    a unit whose slot has been RECYCLED is left alone\n");
    ResetCircleCounters();
    {
        ScCircleUnit set[2] = { CircleFor(50), CircleFor(51) };
        ScCirclesShow(set, 2);
        // Bump the uniqueness byte the way 0x004A03FD does. That instruction is the
        // ONLY write to CUnit+0xA5 in the whole binary and it lives in unit CREATION
        // (0x004A0320), so this models SLOT REUSE, not death -- see
        // research/selection-circles.md 4.5. Reuse is what makes blind removal
        // dangerous: the flag bit may be set again, but by somebody else's circle.
        *(BYTE*)(FakeUnit(50) + SC_CUNIT_OFF_UNIQUENESS) += 1;
        ResetCircleCounters();
        ScCirclesHide();
        Check("only the survivor is detached", (long long)g_removeCalls, 1);
        Check("  it was unit 51's sprite", (long long)g_removedSprites[0], FakeSprite(51));
        *(BYTE*)(FakeUnit(50) + SC_CUNIT_OFF_UNIQUENESS) -= 1;
        *(BYTE*)(FakeSprite(50) + SC_CSPRITE_OFF_FLAGS) = 0;
    }

    printf("\n    a unit that DIED -- the engine already took our circle off\n");
    ResetCircleCounters();
    {
        // What death actually does: 0x004A0740 (the unit-removal path) calls
        // 0x004975D0 on the way out, which frees the 0x231..0x23A image and clears
        // flag 0x01 -- regardless of flag 0x08, so it takes OUR circle too. Death does
        // NOT bump CUnit+0xA5. So the record that protects us here is the flag check,
        // not the uniqueness check, and a second remove must not be attempted.
        ScCircleUnit set[2] = { CircleFor(58), CircleFor(59) };
        ScCirclesShow(set, 2);
        *(BYTE*)(FakeSprite(58) + SC_CSPRITE_OFF_FLAGS) &= (BYTE)~SC_SPRITE_FLAG_SEL_CIRCLE;
        ResetCircleCounters();
        ScCirclesHide();
        Check("the dead unit's circle is not removed twice", (long long)g_removeCalls, 1);
        Check("  the survivor is the one removed", (long long)g_removedSprites[0], FakeSprite(59));
    }

    printf("\n    a unit whose sprite was swapped underneath us is left alone\n");
    ResetCircleCounters();
    {
        ScCircleUnit set[1] = { CircleFor(52) };
        ScCirclesShow(set, 1);
        *(DWORD*)(FakeUnit(52) + SC_CUNIT_OFF_SPRITE) = FakeSprite(53);
        ScCirclesHide();
        Check("nothing detached", (long long)g_removeCalls, 0);
        *(DWORD*)(FakeUnit(52) + SC_CUNIT_OFF_SPRITE) = FakeSprite(52);
        *(BYTE*)(FakeSprite(52) + SC_CSPRITE_OFF_FLAGS) = 0;
    }

    printf("\n    an exhausted image free list is survived, not recorded\n");
    ResetCircleCounters();
    {
        g_addFails = true;
        ScCircleUnit set[2] = { CircleFor(54), CircleFor(55) };
        ScCirclesShow(set, 2);
        Check("both attaches were attempted", (long long)g_addCalls, 2);
        Check("neither was recorded", ScCirclesCount(), 0);
        Check("no flag was set on a sprite with no image",
              *(BYTE*)(FakeSprite(54) + SC_CSPRITE_OFF_FLAGS), 0);
        g_addFails = false;
    }

    printf("\n    a unit with no sprite at all is skipped, not dereferenced\n");
    ResetCircleCounters();
    {
        *(DWORD*)(FakeUnit(56) + SC_CUNIT_OFF_SPRITE) = 0;
        ScCircleUnit set[2] = { CircleFor(56), CircleFor(57) };
        ScCirclesShow(set, 2);
        Check("only the unit with a sprite was attached", (long long)g_addCalls, 1);
        ScCirclesHide();
    }

    Check("FINAL: flag 0x08 was never set on any sprite", NoSpriteWasMarkedSelected(64) ? 1 : 0, 1);
    Check("FINAL: selectionIndex was never written",       NoSelectionIndexWasWritten(64) ? 1 : 0, 1);

    ScCirclesInit(NULL, false);   // leave the module inert
    VirtualFree(g_fake, 0, MEM_RELEASE);
    g_fake = NULL;
}

// ---------------------------------------------------------------------------
// [10] The HUD-row paging (task 017), driven against a fake dialog tree.
//
// sc_hudrow reaches the engine through six pointers (show/hide/update control,
// the button interact, and the two detour originals), so the whole page machine
// -- refresh, page math, the wrap, the splice, snap-back-to-page-1, and the
// restore-to-stock transition -- runs here with no StarCraft in the process.
// The fake sprites from part [8] are kept poisoned throughout: this module never
// touches a sprite, and the final assertions prove it the same way part [8] does.
//
// What is NOT provable offline is whether the engine draws the page and routes
// real dialog events -- that is what tools/plugin/test-hud-row.ps1 is for.
// ---------------------------------------------------------------------------

#define FAKE_DLG_VA      0x00690000u
#define FAKE_STATUSER_VA 0x00691000u

static unsigned g_ctlShows = 0, g_ctlHides = 0, g_ctlUpdates = 0;
static unsigned g_engInteractCalls = 0;
static unsigned g_origDispatchCalls = 0;

static void FakeShowCtl(DWORD ctrl)   { ++g_ctlShows;   *(DWORD*)(ctrl + SC_BINDLG_OFF_FLAGS) |= SC_CTRL_FLAG_VISIBLE; }
static void FakeHideCtl(DWORD ctrl)   { ++g_ctlHides;   *(DWORD*)(ctrl + SC_BINDLG_OFF_FLAGS) &= ~(DWORD)SC_CTRL_FLAG_VISIBLE; }
static void FakeUpdateCtl(DWORD ctrl) { ++g_ctlUpdates; (void)ctrl; }

static int __attribute__((fastcall)) FakeEngineInteract(DWORD ctrl, DWORD evt) {
    (void)ctrl; (void)evt;
    ++g_engInteractCalls;
    return 0;
}

static void FakeOrigDispatch(void) { ++g_origDispatchCalls; }

static DWORD FakeCtl(int i)      { return (DWORD)FakeRt(FAKE_DLG_VA) + 0x100u + (DWORD)i * SC_BINDLG_SIZE; }
static DWORD FakeStatUser(int i) { return (DWORD)FakeRt(FAKE_STATUSER_VA) + (DWORD)i * 8u; }
static DWORD FakeRoot(void)      { return (DWORD)FakeRt(FAKE_DLG_VA); }

// Root dialog + one non-button control (id 1) + the 12 wireframe buttons
// (ids 0x21..0x2C), statUser records poisoned so "nobody wrote it" is
// distinguishable from "somebody wrote 0".
static void BuildFakeDialog(void) {
    const DWORD engineFn = (DWORD)FakeRt(SC_VA_WIREFRAME_BTN_INTERACT);
    DWORD root = FakeRoot();
    memset((void*)root, 0, SC_BINDLG_SIZE);
    *(WORD*)(root + SC_BINDLG_OFF_TYPE) = 0;                    // a dialog

    for (int i = 0; i < 13; ++i) {
        DWORD c = FakeCtl(i);
        memset((void*)c, 0, SC_BINDLG_SIZE);
        *(WORD*) (c + SC_BINDLG_OFF_TYPE)   = (i == 0) ? 5 : 2; // image, then buttons
        *(short*)(c + SC_BINDLG_OFF_INDEX)  = (i == 0) ? 1 : (short)(SC_HUD_FIRST_SMALL_BUTTON + i - 1);
        *(DWORD*)(c + SC_BINDLG_OFF_PARENT) = root;
        *(DWORD*)(c + SC_BINDLG_OFF_NEXT)   = (i < 12) ? FakeCtl(i + 1) : 0;
        short* b = (short*)(c + SC_BINDLG_OFF_BOUNDS);
        b[0] = (short)(166 + (i % 6) * 36); b[1] = (short)(398 + (i / 6) * 34);
        b[2] = (short)(b[0] + 34);          b[3] = (short)(b[1] + 32);
        if (i > 0) {
            *(DWORD*)(c + SC_BINDLG_OFF_INTERACT) = engineFn;
            *(DWORD*)(c + SC_BINDLG_OFF_USER)     = FakeStatUser(i - 1);
            *(DWORD*)(FakeStatUser(i - 1) + SC_STATUSER_OFF_UNIT) = 0xEEEEEEEEu;
            *(WORD*) (FakeStatUser(i - 1) + SC_STATUSER_OFF_ID)   = 0xEEEE;
        }
    }
    *(DWORD*)(root + SC_BINDLG_OFF_FIRST_CHILD) = FakeCtl(0);

    // The per-type default handler tables the indicator control reads its
    // draw/interact from (type 9 = LSTATIC).
    *(DWORD*)((DWORD)FakeRt(SC_VA_DEFAULT_INTERACT_TABLE) + 9 * 4) = 0x11111111u;
    *(DWORD*)((DWORD)FakeRt(SC_VA_DEFAULT_UPDATE_TABLE)   + 9 * 4) = 0x22222222u;
    *(BYTE*)FakeRt(SC_VA_STAT_ALL_HIDDEN) = 0;
    *(BYTE*)FakeRt(SC_VA_STAT_DIRTY)      = 0;
}

static int CountChildren(void) {
    int n = 0;
    for (DWORD c = *(DWORD*)(FakeRoot() + SC_BINDLG_OFF_FIRST_CHILD); c && n < 32;
         c = *(DWORD*)(c + SC_BINDLG_OFF_NEXT)) ++n;
    return n;
}

static DWORD ShownStatUserUnit(int btn) {   // 0-based button index
    return *(DWORD*)(FakeStatUser(btn) + SC_STATUSER_OFF_UNIT);
}

static void SmallSelection(int n) {
    DWORD v[SC_SELECTION_SLOTS];
    for (int i = 0; i < n; ++i) v[i] = FakeUnit(i);
    ScFanoutOnSelect((unsigned)n, v);
}

// Point the dispatcher's two globals at the fake dialog + a live portrait unit.
static void SetHudGlobals(DWORD dialog, DWORD portrait) {
    *(DWORD*)FakeRt(SC_VA_STATDATA_DIALOG)      = dialog;
    *(DWORD*)FakeRt(SC_VA_ACTIVE_PORTRAIT_UNIT) = portrait;
    *(BYTE*) FakeRt(SC_VA_STAT_DIRTY)           = 0;
}

// Keep the fake clientSelectionGroup (0x00597208) in sync with the engine's
// visible <=12, so RefreshShadow's engine-selection comparison runs for real in
// the test instead of firing spuriously on a zero page. `n` units, zero-padded.
static void SetEngineSelection(const DWORD* units, int n) {
    DWORD* g = (DWORD*)FakeRt(SC_VA_CLIENT_SELECTION_GROUP);
    for (int i = 0; i < 12; ++i) g[i] = (i < n) ? units[i] : 0;
}
static void SetEngineSelectionFirst(int n) {   // FakeUnit(0..n-1)
    DWORD u[12];
    for (int i = 0; i < n && i < 12; ++i) u[i] = FakeUnit(i);
    SetEngineSelection(u, n < 12 ? n : 12);
}

// A >12 or <=12 selection PLUS the matching engine visible selection, so
// RefreshShadow's engine-mismatch snap does not fire spuriously.
static void Drive36Sync(void)   { DriveSelection(36); SetEngineSelectionFirst(12); }
static void SmallSync(int n)    { SmallSelection(n);  SetEngineSelectionFirst(n); }

// Link FakeUnit(0..n-1) into the fake playerUnitList[player] via +0x68/+0x6C, so
// the click gate's InPlayerUnitList walk runs for real. Head-insert.
static void BuildFakePlayerList(int n, BYTE player) {
    DWORD* heads = (DWORD*)FakeRt(SC_VA_PLAYER_UNIT_LIST);
    heads[player] = 0;
    for (int i = 0; i < n; ++i) {
        DWORD u = FakeUnit(i);
        *(DWORD*)(u + SC_CUNIT_OFF_LIST_PREV) = 0;
        *(DWORD*)(u + SC_CUNIT_OFF_LIST_NEXT) = heads[player];
        if (heads[player]) *(DWORD*)(heads[player] + SC_CUNIT_OFF_LIST_PREV) = u;
        heads[player] = u;
    }
}
static void UnlinkFakeUnit(int i, BYTE player) {   // models removal from play
    DWORD* heads = (DWORD*)FakeRt(SC_VA_PLAYER_UNIT_LIST);
    DWORD u = FakeUnit(i);
    DWORD prev = *(DWORD*)(u + SC_CUNIT_OFF_LIST_PREV);
    DWORD next = *(DWORD*)(u + SC_CUNIT_OFF_LIST_NEXT);
    if (prev) *(DWORD*)(prev + SC_CUNIT_OFF_LIST_NEXT) = next; else heads[player] = next;
    if (next) *(DWORD*)(next + SC_CUNIT_OFF_LIST_PREV) = prev;
    *(DWORD*)(u + SC_CUNIT_OFF_LIST_NEXT) = 0;
    *(DWORD*)(u + SC_CUNIT_OFF_LIST_PREV) = 0;
}
static void RelinkFakeUnit(int i, BYTE player) {   // put it back, for cleanup
    DWORD* heads = (DWORD*)FakeRt(SC_VA_PLAYER_UNIT_LIST);
    DWORD u = FakeUnit(i);
    *(DWORD*)(u + SC_CUNIT_OFF_LIST_PREV) = 0;
    *(DWORD*)(u + SC_CUNIT_OFF_LIST_NEXT) = heads[player];
    if (heads[player]) *(DWORD*)(heads[player] + SC_CUNIT_OFF_LIST_PREV) = u;
    heads[player] = u;
}

// A dialog USER/ACTIVATE event (the select notification) built into `buf` (>= 0x14).
static void MakeActivateEvt(BYTE* buf) {
    memset(buf, 0, 0x14);
    *(DWORD*)(buf + SC_EVT_OFF_USER) = SC_USER_ACTIVATE;   // dwUser = 2
    *(WORD*) (buf + SC_EVT_OFF_TYPE) = SC_EVT_TYPE_USER;   // type  = 14
}
static void MakeRButtonEvt(BYTE* buf) {
    memset(buf, 0, 0x14);
    *(WORD*)(buf + SC_EVT_OFF_TYPE) = SC_EVT_RBUTTONDOWN;  // type = 7
}

static void ResetHudCounters(void) {
    g_ctlShows = g_ctlHides = g_ctlUpdates = 0;
    g_engInteractCalls = g_origDispatchCalls = 0;
}

static void HudRowTests(void) {
    printf("\n[10] HUD-row paging: fake dialog tree, fake engine primitives\n");

    g_fake = (BYTE*)VirtualAlloc(NULL, FAKE_IMAGE_BYTES, MEM_COMMIT | MEM_RESERVE,
                                 PAGE_READWRITE);
    if (!g_fake) { printf("  FAIL could not allocate the fake image\n"); ++g_failures; return; }

    MakeUnits(64, 1);
    MakeSprites(64);                          // poisoned selectionIndex, part [8] style
    for (int i = 0; i < 64; ++i) {            // give every unit a type id and HP
        *(WORD*) (FakeUnit(i) + SC_CUNIT_OFF_UNIT_ID)   = (WORD)(100 + i);
        *(DWORD*)(FakeUnit(i) + SC_CUNIT_OFF_HITPOINTS) = 40 * 256;
    }
    BuildFakePlayerList(64, 1);               // all in play (player 1), for the click gate

    ScFanoutTestBegin(g_fake, NULL, 200);     // shadow-list source; no emission
    BuildFakeDialog();
    ScHudRowTestBegin(g_fake, &FakeShowCtl, &FakeHideCtl, &FakeUpdateCtl,
                      &FakeEngineInteract, &FakeOrigDispatch);

    const DWORD engineFn = (DWORD)FakeRt(SC_VA_WIREFRAME_BTN_INTERACT);
    const DWORD root     = FakeRoot();
    SetHudGlobals(root, FakeUnit(0));         // dialog + a live portrait unit

    printf("\n    a <=12 selection stays stock: the engine's dispatcher runs, nothing touched\n");
    ResetHudCounters();
    SmallSync(10);
    ScHudRowOnDispatch();
    Check("the original dispatcher ran", (long long)g_origDispatchCalls, 1);
    Check("button 1 interact still the engine's",
          (long long)*(DWORD*)(FakeCtl(1) + SC_BINDLG_OFF_INTERACT), (long long)engineFn);
    Check("statUser 0 untouched (poison intact)", (long long)ShownStatUserUnit(0),
          (long long)0xEEEEEEEEu);
    Check("child count unchanged (no indicator)", CountChildren(), 13);

    printf("\n    36 units: page 1 is the ENGINE'S OWN 12\n");
    ResetHudCounters();
    Drive36Sync();
    ScHudRowOnDispatch();
    Check("the engine's dispatcher was NOT called (we stood in for it)",
          (long long)g_origDispatchCalls, 0);
    Check("page 1 of 3", ScHudRowCurrentPage() + 1, 1);
    Check("page count 3", ScHudRowPageCount(), 3);
    {
        bool slotsOk = true, wrapOk = true, wrapUniform = true;
        DWORD wrapVal = *(DWORD*)(FakeCtl(1) + SC_BINDLG_OFF_INTERACT);
        for (int i = 0; i < 12; ++i) {
            if (ShownStatUserUnit(i) != FakeUnit(i)) slotsOk = false;
            if (*(WORD*)(FakeStatUser(i) + SC_STATUSER_OFF_ID) != (WORD)(100 + i)) slotsOk = false;
            DWORD w = *(DWORD*)(FakeCtl(1 + i) + SC_BINDLG_OFF_INTERACT);
            if (w == engineFn || w == 0) wrapOk = false;
            if (w != wrapVal) wrapUniform = false;
        }
        Check("the 12 statUser records hold visible units 1-12", slotsOk ? 1 : 0, 1);
        Check("all 12 buttons wrapped away from the engine fn", wrapOk ? 1 : 0, 1);
        Check("  with one uniform shim", wrapUniform ? 1 : 0, 1);
    }
    Check("the indicator is spliced (14 children)", CountChildren(), 14);
    {
        DWORD ind = *(DWORD*)(root + SC_BINDLG_OFF_FIRST_CHILD);
        Check("  at the head, with a negative id",
              (long long)*(short*)(ind + SC_BINDLG_OFF_INDEX), (long long)(short)0xFFE0);
        Check("  interact from the type-9 default table",
              (long long)*(DWORD*)(ind + SC_BINDLG_OFF_INTERACT), 0x11111111);
        Check("  update from the type-9 default table",
              (long long)*(DWORD*)(ind + SC_BINDLG_OFF_UPDATE), 0x22222222);
        const char* text = (const char*)*(DWORD*)(ind + SC_BINDLG_OFF_TEXT);
        Check("  text says 36 units, 1-12, page 1/3",
              (text && strstr(text, "36 units") && strstr(text, "1-12") &&
               strstr(text, "(1/3)")) ? 1 : 0, 1);
    }
    // A quiet frame: dispatcher runs, but nothing changed -> no re-fill and the
    // engine's dispatcher stays untouched (the page persists on its own).
    ResetHudCounters();
    ScHudRowOnDispatch();
    Check("a settled frame does not re-show the buttons", (long long)g_ctlShows, 0);
    Check("  and does not call the engine's dispatcher", (long long)g_origDispatchCalls, 0);

    printf("\n    right-click flips pages; every other event passes through\n");
    {
        BYTE evt[0x14];
        memset(evt, 0, sizeof(evt));
        *(WORD*)(evt + SC_EVT_OFF_TYPE) = SC_EVT_RBUTTONDOWN;
        Check("right-click handled", ScHudRowOnButtonEvent(FakeCtl(3), (DWORD)&evt[0]), 1);
        Check("  dirty flag raised", (long long)*(BYTE*)FakeRt(SC_VA_STAT_DIRTY), 1);
        ScHudRowOnDispatch();
        Check("  page 2 of 3", ScHudRowCurrentPage() + 1, 2);
        Check("  dirty flag consumed", (long long)*(BYTE*)FakeRt(SC_VA_STAT_DIRTY), 0);
        bool slotsOk = true;
        for (int i = 0; i < 12; ++i) {
            if (ShownStatUserUnit(i) != FakeUnit(12 + i)) slotsOk = false;
        }
        Check("  page 2 shows overflow units 13-24", slotsOk ? 1 : 0, 1);
        {
            DWORD ind = *(DWORD*)(root + SC_BINDLG_OFF_FIRST_CHILD);
            const char* text = (const char*)*(DWORD*)(ind + SC_BINDLG_OFF_TEXT);
            Check("  indicator says 13-24 (2/3)",
                  (text && strstr(text, "13-24") && strstr(text, "(2/3)")) ? 1 : 0, 1);
        }
        ResetHudCounters();
        *(WORD*)(evt + SC_EVT_OFF_TYPE) = 4;   // LBUTTONDOWN
        ScHudRowOnButtonEvent(FakeCtl(3), (DWORD)&evt[0]);
        Check("  a left-click reaches the engine's handler",
              (long long)g_engInteractCalls, 1);
        *(WORD*)(evt + SC_EVT_OFF_TYPE) = SC_EVT_RBUTTONDOWN;
        ScHudRowOnButtonEvent(FakeCtl(3), (DWORD)&evt[0]);
        ScHudRowOnDispatch();
        Check("  next flip reaches page 3 (units 25-36)",
              ShownStatUserUnit(0) == FakeUnit(24) ? 1 : 0, 1);
        ScHudRowOnButtonEvent(FakeCtl(3), (DWORD)&evt[0]);
        ScHudRowOnDispatch();
        Check("  and wraps back to page 1", ScHudRowCurrentPage() + 1, 1);
    }

    printf("\n    HP drift on the displayed page is noticed\n");
    ResetHudCounters();
    ScHudRowOnDispatch();
    Check("settled again (no re-show)", (long long)g_ctlShows, 0);
    *(DWORD*)(FakeUnit(0) + SC_CUNIT_OFF_HITPOINTS) = 10 * 256;   // unit 0 is on page 1
    ResetHudCounters();
    ScHudRowOnDispatch();
    Check("a displayed unit losing HP forces a re-fill", g_ctlShows > 0 ? 1 : 0, 1);

    printf("\n    a unit DYING (HP->0, uniqueness UNCHANGED) snaps back to page 1\n");
    // The blocker fix: death is detected by HP==0, NOT by the uniqueness byte --
    // research/selection-circles.md 4.5 proves death does not bump 0xA5. Unit 15 is
    // an OVERFLOW unit (page 2), so this isolates HP-death from the engine-selection
    // path (clientSelectionGroup, the visible 12, is untouched).
    {
        BYTE evt[0x14];
        memset(evt, 0, sizeof(evt));
        *(WORD*)(evt + SC_EVT_OFF_TYPE) = SC_EVT_RBUTTONDOWN;
        ScHudRowOnButtonEvent(FakeCtl(3), (DWORD)&evt[0]);
        ScHudRowOnDispatch();
        Check("on page 2", ScHudRowCurrentPage() + 1, 2);
        BYTE uniqBefore = *(BYTE*)(FakeUnit(15) + SC_CUNIT_OFF_UNIQUENESS);
        *(DWORD*)(FakeUnit(15) + SC_CUNIT_OFF_HITPOINTS) = 0;    // real death
        Check("  uniqueness is UNCHANGED by death (0xA5 does not move)",
              (long long)*(BYTE*)(FakeUnit(15) + SC_CUNIT_OFF_UNIQUENESS), (long long)uniqBefore);
        ScHudRowOnDispatch();
        Check("HP==0 death snapped back to page 1", ScHudRowCurrentPage() + 1, 1);
        Check("  35 live units, still 3 pages", ScHudRowPageCount(), 3);
        {
            DWORD ind = *(DWORD*)(root + SC_BINDLG_OFF_FIRST_CHILD);
            const char* text = (const char*)*(DWORD*)(ind + SC_BINDLG_OFF_TEXT);
            Check("  indicator says 35 units", (text && strstr(text, "35 units")) ? 1 : 0, 1);
        }
        *(DWORD*)(FakeUnit(15) + SC_CUNIT_OFF_HITPOINTS) = 40 * 256;   // revive for later cases
    }

    printf("\n    a RECYCLED slot (uniqueness bumped) is dropped too -- the other case\n");
    {
        BYTE evt[0x14];
        memset(evt, 0, sizeof(evt));
        *(WORD*)(evt + SC_EVT_OFF_TYPE) = SC_EVT_RBUTTONDOWN;
        ScHudRowOnButtonEvent(FakeCtl(3), (DWORD)&evt[0]);
        ScHudRowOnDispatch();
        Check("on page 2 again", ScHudRowCurrentPage() + 1, 2);
        *(BYTE*)(FakeUnit(16) + SC_CUNIT_OFF_UNIQUENESS) += 1;   // slot reused (0x004A0320)
        ScHudRowOnDispatch();
        Check("reuse snapped back to page 1", ScHudRowCurrentPage() + 1, 1);
        {
            DWORD ind = *(DWORD*)(root + SC_BINDLG_OFF_FIRST_CHILD);
            const char* text = (const char*)*(DWORD*)(ind + SC_BINDLG_OFF_TEXT);
            Check("  indicator says 35 units (only unit 16 dropped)",
                  (text && strstr(text, "35 units")) ? 1 : 0, 1);
        }
        *(BYTE*)(FakeUnit(16) + SC_CUNIT_OFF_UNIQUENESS) -= 1;
    }

    printf("\n    PERSISTENT engine divergence hands back to stock and stays there\n");
    // An engine-side removal that bypassed CMDACT_Select (transport, mind control,
    // trigger RemoveUnit): the visible unit is gone from clientSelectionGroup but the
    // version counter never moved. The row must hand back to stock and STAY stock
    // (no per-frame churn, flip structurally dead) until the next real commit.
    {
        Drive36Sync();
        ScHudRowOnDispatch();                                   // paged, page 1
        Check("paged before divergence", ScHudRowPageCount(), 3);
        DWORD* g = (DWORD*)FakeRt(SC_VA_CLIENT_SELECTION_GROUP);
        DWORD saved = g[5]; g[5] = 0;                           // engine dropped a visible unit
        ResetHudCounters();
        ScHudRowOnDispatch();
        Check("divergence handed back to stock (engine dispatcher ran)",
              (long long)g_origDispatchCalls, 1);
        Check("  latched diverged", ScHudRowIsDiverged() ? 1 : 0, 1);
        {
            bool restored = true;
            for (int i = 0; i < 12; ++i)
                if (*(DWORD*)(FakeCtl(1+i) + SC_BINDLG_OFF_INTERACT) != engineFn) restored = false;
            Check("  all 12 buttons restored to engine interact (flip now dead)",
                  restored ? 1 : 0, 1);
        }
        Check("  the indicator is unspliced", CountChildren(), 13);
        ResetHudCounters();
        for (int k = 0; k < 4; ++k) ScHudRowOnDispatch();
        Check("  stays stock over 4 frames: no re-show churn", (long long)g_ctlShows, 0);
        Check("  engine dispatcher ran each of the 4 frames", (long long)g_origDispatchCalls, 4);
        // Heal: restore the engine selection AND a new commit (version bump).
        g[5] = saved;
        Drive36Sync();
        ResetHudCounters();
        ScHudRowOnDispatch();
        Check("a new commit heals divergence and resumes paging", g_ctlShows > 0 ? 1 : 0, 1);
        Check("  no longer diverged", ScHudRowIsDiverged() ? 1 : 0, 0);
    }

    printf("\n    the CLICK GATE swallows a click on a removed-not-killed OVERFLOW unit\n");
    // The exposure (b) closes: an overflow unit loaded into a transport is unlinked
    // from its player unit list but keeps HP and uniqueness, and is NOT in
    // clientSelectionGroup (so the divergence check cannot see it). A click on its
    // portrait must be swallowed before the engine's Select ever sees the stale ptr.
    {
        BYTE rbtn[0x14], act[0x14];
        MakeRButtonEvt(rbtn);
        MakeActivateEvt(act);
        Drive36Sync();
        ScHudRowOnDispatch();                                   // page 1
        ScHudRowOnButtonEvent(FakeCtl(3), (DWORD)&rbtn[0]);     // -> page 2
        ScHudRowOnDispatch();
        Check("on page 2 (units 13-24)", ScHudRowCurrentPage() + 1, 2);
        // Unit 15 is shown on page-2 button 4 (disp[15] = FakeUnit(15)). Remove it
        // from play: HP and uniqueness UNCHANGED, gone from the player unit list.
        Check("  button 4 shows unit 15", ShownStatUserUnit(3) == FakeUnit(15) ? 1 : 0, 1);
        UnlinkFakeUnit(15, 1);
        ResetHudCounters();
        int r = ScHudRowOnButtonEvent(FakeCtl(4), (DWORD)&act[0]);
        Check("the click on the removed unit is SWALLOWED", (long long)r, 1);
        Check("  the engine interact was NOT called", (long long)g_engInteractCalls, 0);
        Check("  the gate counted it", ScHudRowGatedCount(), 1);
        Check("  latched diverged -> next frame hands to stock", ScHudRowIsDiverged() ? 1 : 0, 1);
        ScHudRowOnDispatch();
        Check("  handed back to stock", (long long)g_origDispatchCalls, 1);

        // Contrast: a VALID unit's click passes through to the engine.
        RelinkFakeUnit(15, 1);
        Drive36Sync();
        ScHudRowOnDispatch();                                   // page 1, fresh
        ScHudRowOnButtonEvent(FakeCtl(3), (DWORD)&rbtn[0]);     // -> page 2
        ScHudRowOnDispatch();
        ResetHudCounters();
        int r2 = ScHudRowOnButtonEvent(FakeCtl(4), (DWORD)&act[0]);
        Check("a valid unit's ACTIVATE is NOT swallowed", (long long)r2, 0);
        Check("  it reaches the engine interact", (long long)g_engInteractCalls, 1);
        Check("  the gate count did not rise", ScHudRowGatedCount(), 1);
    }

    printf("\n    a selection change to ONE unit restores the row to stock\n");
    // The single-unit case the dispatcher detour exists for: the engine's own
    // single branch never calls the multi act, so the hand-back must come from the
    // dispatcher detour itself.
    ResetHudCounters();
    SmallSync(1);
    ScHudRowOnDispatch();
    Check("the engine's dispatcher ran the hand-back", (long long)g_origDispatchCalls, 1);
    {
        bool restored = true;
        for (int i = 0; i < 12; ++i) {
            if (*(DWORD*)(FakeCtl(1 + i) + SC_BINDLG_OFF_INTERACT) != engineFn) restored = false;
        }
        Check("all 12 interact pointers restored to the engine fn", restored ? 1 : 0, 1);
    }
    Check("the indicator is unspliced (13 children)", CountChildren(), 13);
    Check("buttons force-repainted over the indicator's pixels",
          g_ctlUpdates > 0 ? 1 : 0, 1);
    ResetHudCounters();
    ScHudRowOnDispatch();
    Check("and it stays stock (engine dispatcher keeps running)",
          (long long)g_origDispatchCalls, 1);

    printf("\n    re-entering overflow re-wraps and re-splices exactly once\n");
    Drive36Sync();
    ScHudRowOnDispatch();
    ScHudRowOnDispatch();                     // idempotence: a second frame changes nothing
    Check("still 14 children after two frames", CountChildren(), 14);

    printf("\n    THE INVARIANT: this module never touches a sprite\n");
    Check("flag 0x08 was never set on any sprite", NoSpriteWasMarkedSelected(64) ? 1 : 0, 1);
    Check("selectionIndex was never written", NoSelectionIndexWasWritten(64) ? 1 : 0, 1);

    printf("\n    the DISABLED module is a pure passthrough (g_enabled == false)\n");
    // NULL base -> ScHudRowTestBegin leaves the module disabled but keeps the seam,
    // so the "!g_enabled -> CallOrigDispatch" path is observable.
    ScHudRowTestBegin(NULL, &FakeShowCtl, &FakeHideCtl, &FakeUpdateCtl,
                      &FakeEngineInteract, &FakeOrigDispatch);
    ResetHudCounters();
    Drive36Sync();                            // even a >12 selection...
    ScHudRowOnDispatch();
    Check("disabled: the engine's dispatcher ran", (long long)g_origDispatchCalls, 1);
    Check("disabled: no control was shown", (long long)g_ctlShows, 0);
    {
        // A REAL right-click event, so only g_enabled separates this from the enabled
        // flip case -- not a degenerate evt==0.
        BYTE rbtn[0x14];
        MakeRButtonEvt(rbtn);
        Check("disabled: a real right-click is NOT intercepted",
              (long long)ScHudRowOnButtonEvent(FakeCtl(3), (DWORD)&rbtn[0]), 0);
        Check("disabled: it reached the engine interact instead",
              (long long)g_engInteractCalls, 1);
    }

    ScHudRowTestBegin(NULL, NULL, NULL, NULL, NULL, NULL);   // leave it inert
    ScFanoutTestBegin(NULL, NULL, 200);
    VirtualFree(g_fake, 0, MEM_RELEASE);
    g_fake = NULL;
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

    FanoutCoreTests();
    OpcodePolicyTests();
    CircleTests();
    HudRowTests();

    printf("\nhooktest: %d failure(s)\n", g_failures);
    ScLogClose();
    return g_failures == 0 ? 0 : 1;
}
