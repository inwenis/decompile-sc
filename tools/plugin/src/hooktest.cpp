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
#include "sc_card.h"
#include "sc_circles.h"
#include "sc_fanout.h"
#include "sc_hook.h"
#include "sc_hudrow.h"
#include "sc_queueind.h"
#include "sc_log.h"
#include "sc_prodfan.h"
#include "sc_prodqueue.h"
#include "sc_screen.h"
#include "sc_session.h"
#include "sc_upgrades.h"
#include "sc_unit.h"

static int g_failures = 0;

// ---------------------------------------------------------------------------
// Parts: numbered by the order they RUN, never by hand (issue #35)
//
// Three separate branches claimed a part number that another branch had already
// taken -- 024 and 026 both took [13], 021 and 025 both took [11], 028 and 029 both
// took [16]. Every one of them was invisible until somebody merged both sides: the
// declarations sit in different regions of this file (or in different files), so git
// reports no conflict and both parts simply arrive with the same number.
//
// The number exists for exactly one purpose: naming which part failed in a redirected
// overnight log. Two parts sharing one defeats that purpose precisely when it is
// needed. So the number is no longer a thing a branch claims -- Part() assigns it from
// the order the parts actually run in, and prints the part's NAME beside it. There is
// nothing left to collide over, and adding a part is one call with no shared resource
// to check first.
//
// The NAME is now the real identifier: Check() prints it on every failing line, so a
// reader greppping a 4000-line log for FAIL learns the subsystem without scrolling back
// to a header. Duplicate names are refused below, for the same reason duplicate numbers
// were a defect.
//
// The call order at the bottom of main() is deliberately chosen so the derived numbers
// still match the ones research/ already cites (control-groups.md cites part [11] four
// times, selection-circles.md cites [8], and so on). NEW PARTS GO AT THE END and take
// the next number automatically. Reordering existing calls renumbers them and silently
// invalidates those citations, so don't -- unless you are also fixing the citations.
// ---------------------------------------------------------------------------
#define SC_MAX_PARTS 64
static int g_partCount = 0;
static const char* g_partNames[SC_MAX_PARTS];
static const char* g_partName = "(before any part)";

static void Part(const char* name) {
    for (int i = 0; i < g_partCount && i < SC_MAX_PARTS; ++i) {
        if (strcmp(g_partNames[i], name) == 0) {
            printf("  FAIL duplicate hooktest part name '%s' -- already part [%d]\n", name, i + 1);
            ++g_failures;
        }
    }
    if (g_partCount < SC_MAX_PARTS) { g_partNames[g_partCount] = name; }
    else { printf("  FAIL more than %d parts; raise SC_MAX_PARTS\n", SC_MAX_PARTS); ++g_failures; }
    ++g_partCount;
    g_partName = name;
    printf("\n[%d] %s\n", g_partCount, name);
}

static void Check(const char* what, long long got, long long want) {
    if (got == want) {
        printf("  ok   %-46s = %lld\n", what, got);
    } else {
        // The part NAME on the failing line itself. "part [16] failed" was unanswerable
        // when two parts held [16]; "[16] the status pane's production-queue strip" is
        // answerable however the numbering came out.
        printf("  FAIL %-46s = %lld (expected %lld)   <- [%d] %s\n",
               what, got, want, g_partCount, g_partName);
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

// Defined with parts [8] and [10], used here: a unit is only "live" to sc_fanout's
// task-020 gate if it has a sprite and is linked into its player's unit list, so
// every part that drives the fan-out core needs both.
static void MakeSprites(int n);
static void BuildFakePlayerList(int n, BYTE player);
static void UnlinkFakeUnit(int i, BYTE player);
static void RelinkFakeUnit(int i, BYTE player);

// A block of units in the state the engine leaves a unit that is IN PLAY: a
// uniqueness byte, an owner, hit points, a sprite, and a place in
// playerUnitList[owner]. Every one of those is a term of the emit-side liveness gate
// (sc_fanout.cpp, "LIVENESS"), so a test that wants a unit to be emitted has to set
// all of them -- and a test that wants one DROPPED breaks exactly one and says which.
static void MakeUnits(int n, BYTE player) {
    for (int i = 0; i < n; ++i) {
        BYTE* u = (BYTE*)FakeUnit(i);
        u[SC_CUNIT_OFF_UNIQUENESS] = (BYTE)(1 + (i % 7));   // varied, so a wrong
        u[SC_CUNIT_OFF_PLAYER]     = player;                // index shows up as a
        *(DWORD*)(u + SC_CUNIT_OFF_HITPOINTS) = 40 * 256;   // wrong tag
    }
    MakeSprites(n);
    BuildFakePlayerList(n, player);
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

// Walks the capture as the wire stream it is -- Select(0x09) then a fixed-length
// order, repeating -- and answers whether `tag` is in ANY emitted Select. That is the
// question task 020's gate is about: not "how many units went out" but "did THIS
// unit's tag reach the receive path".
static bool CaptureHasTag(WORD tag, int orderLen) {
    int off = 0;
    while (off + 2 <= g_captureLen) {
        if (g_capture[off] != SC_CMD_SELECT) { off += orderLen; continue; }
        const int n = g_capture[off + 1];
        for (int i = 0; i < n && off + 4 + i * 2 <= g_captureLen; ++i) {
            WORD t = (WORD)(g_capture[off + 2 + i * 2] | (g_capture[off + 3 + i * 2] << 8));
            if (t == tag) return true;
        }
        off += 2 + n * 2;
    }
    return false;
}

// How many unit tags all the emitted Selects carry between them.
static int CaptureTagCount(int orderLen) {
    int off = 0, n = 0;
    while (off + 2 <= g_captureLen) {
        if (g_capture[off] != SC_CMD_SELECT) { off += orderLen; continue; }
        n += g_capture[off + 1];
        off += 2 + g_capture[off + 1] * 2;
    }
    return n;
}

static int ExpectOrderAt(const char* what, int off) {
    bool ok = (off + (int)sizeof(kRightClick) <= g_captureLen) &&
              memcmp(g_capture + off, kRightClick, sizeof(kRightClick)) == 0;
    Check(what, ok ? 1 : 0, 1);
    return off + (int)sizeof(kRightClick);
}

static void FanoutCoreTests(void) {
    Part("the fan-out core: 36 units, one right-click, no game, no hooks");

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

    printf("\n    SLOT REUSE: a recycled slot (uniqueness bumped) is dropped\n");
    ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
    ResetQueueCounters();
    DriveSelection(36);
    // The slot was re-initialised into a different unit: 0x004A0320 bumps CUnit+0xA5
    // (selection-circles.md 4.5), which is the one case the engine's own stale-tag
    // test detects -- and the only one the pre-task-020 gate detected.
    for (int i = 12; i < 15; ++i) *(BYTE*)(FakeUnit(i) + SC_CUNIT_OFF_UNIQUENESS) += 1;
    g_captureLen = 0; g_captureCount = 0;
    ScFanoutOnCommand(kRightClick, sizeof(kRightClick));
    Check("still 3 pairs", g_captureCount, 6);
    Check("first Select carries 9 units, not 12", g_capture[1], 9);
    Check("bytes queued drops by 3 tags (6B)", g_captureLen, 102);
    Check("all three were charged to `recycled`, not to another reason",
          ScFanoutDroppedFor(SC_FANOUT_DROP_RECYCLED), 3);
    Check("and nothing else was dropped", ScFanoutStaleSkipped(), 3);
    for (int i = 12; i < 15; ++i) *(BYTE*)(FakeUnit(i) + SC_CUNIT_OFF_UNIQUENESS) -= 1;

    // ---------------------------------------------------------------------
    // TASK 020. The case the uniqueness test cannot see: a unit killed by DAMAGE.
    //
    // CUnit+0xA5 is written by one instruction in the binary, inside the unit
    // (re)init 0x004A0320 -- so it moves on slot REUSE and NOT on death
    // (selection-circles.md 4.5). A damage-killed unit whose slot has not been
    // recycled therefore still carries the uniqueness we captured, its tag still
    // passes the receive side's check (CMDRECV_Select 0x004C2750), and
    // addUnitToSelectionSlot 0x0049AF80 then dereferences its sprite pointer.
    //
    // The two halves are asserted SEPARATELY -- uniqueness UNCHANGED is what makes
    // this test about the new term rather than the old one.
    // ---------------------------------------------------------------------
    printf("\n    DAMAGE DEATH: hitpoints 0 with uniqueness UNCHANGED -- the 0xA5 case\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        DriveSelection(36);
        const int dead = 13;                       // one of the overflow units
        const BYTE uniqBefore = *(BYTE*)(FakeUnit(dead) + SC_CUNIT_OFF_UNIQUENESS);
        const WORD deadTag = ExpectTag(dead);
        *(DWORD*)(FakeUnit(dead) + SC_CUNIT_OFF_HITPOINTS) = 0;    // 0x004797B0 does this

        g_captureLen = 0; g_captureCount = 0;
        ScFanoutOnCommand(kRightClick, sizeof(kRightClick));

        Check("the unit's uniqueness byte did NOT move, so the engine's own test "
              "would still accept its tag",
              *(BYTE*)(FakeUnit(dead) + SC_CUNIT_OFF_UNIQUENESS), uniqBefore);
        Check("the dead unit's tag is in NO emitted Select",
              CaptureHasTag(deadTag, (int)sizeof(kRightClick)) ? 1 : 0, 0);
        Check("35 of the 36 went out", CaptureTagCount((int)sizeof(kRightClick)), 35);
        Check("it was dropped as a DEATH, not as a recycled slot",
              ScFanoutDroppedFor(SC_FANOUT_DROP_DEAD), 1);
        Check("staleSkipped counted exactly it", ScFanoutStaleSkipped(), 1);
        Check("the order still fanned out over the survivors", g_captureCount, 6);

        // THE POINT, stated as a test: with the gate back at its pre-task-020 shape
        // the very same unit IS replayed. An assertion that cannot fail proves
        // nothing, so the failing configuration is exercised here too.
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ScFanoutTestSetLiveness(false);
        ResetQueueCounters();
        DriveSelection(36);
        g_captureLen = 0; g_captureCount = 0;
        ScFanoutOnCommand(kRightClick, sizeof(kRightClick));
        Check("PRE-FIX (liveness off): the dead unit's tag DOES reach the wire",
              CaptureHasTag(deadTag, (int)sizeof(kRightClick)) ? 1 : 0, 1);
        Check("PRE-FIX: all 36 went out, dead one included",
              CaptureTagCount((int)sizeof(kRightClick)), 36);
        Check("PRE-FIX: nothing was skipped", ScFanoutStaleSkipped(), 0);

        *(DWORD*)(FakeUnit(dead) + SC_CUNIT_OFF_HITPOINTS) = 40 * 256;
    }

    // ---------------------------------------------------------------------
    // The other removal paths. None of them touches hitpoints OR uniqueness, which
    // is why the gate needs a term that is not death-shaped: the unit-list walk.
    // ---------------------------------------------------------------------
    printf("\n    REMOVED FROM PLAY: unlinked from playerUnitList, HP and 0xA5 intact\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        DriveSelection(36);
        const int gone = 20;
        const WORD goneTag = ExpectTag(gone);
        UnlinkFakeUnit(gone, 1);        // what 0x004A0740 does to a unit removed from play

        g_captureLen = 0; g_captureCount = 0;
        ScFanoutOnCommand(kRightClick, sizeof(kRightClick));
        Check("its hitpoints are untouched -- the death term cannot see this one",
              (long long)*(DWORD*)(FakeUnit(gone) + SC_CUNIT_OFF_HITPOINTS), 40 * 256);
        Check("its uniqueness is untouched too",
              *(BYTE*)(FakeUnit(gone) + SC_CUNIT_OFF_UNIQUENESS),
              (long long)(1 + (gone % 7)));
        Check("the removed unit's tag is in NO emitted Select",
              CaptureHasTag(goneTag, (int)sizeof(kRightClick)) ? 1 : 0, 0);
        Check("it was dropped as REMOVED FROM PLAY",
              ScFanoutDroppedFor(SC_FANOUT_DROP_REMOVED), 1);
        Check("35 of the 36 went out", CaptureTagCount((int)sizeof(kRightClick)), 35);
        RelinkFakeUnit(gone, 1);
    }

    printf("\n    OWNERSHIP CHANGE: the slot now belongs to another player\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        DriveSelection(36);
        const int taken = 25;
        const WORD takenTag = ExpectTag(taken);
        *(BYTE*)(FakeUnit(taken) + SC_CUNIT_OFF_PLAYER) = 2;   // mind control relinks it
        g_captureLen = 0; g_captureCount = 0;
        ScFanoutOnCommand(kRightClick, sizeof(kRightClick));
        Check("the tag of a unit that changed hands is in NO emitted Select",
              CaptureHasTag(takenTag, (int)sizeof(kRightClick)) ? 1 : 0, 0);
        Check("dropped as FOREIGN", ScFanoutDroppedFor(SC_FANOUT_DROP_FOREIGN), 1);
        *(BYTE*)(FakeUnit(taken) + SC_CUNIT_OFF_PLAYER) = 1;
    }

    printf("\n    NO SPRITE: the exact pointer 0x0049AF80 dereferences is NULL\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        DriveSelection(36);
        const int bald = 30;
        const WORD baldTag = ExpectTag(bald);
        const DWORD sprite = *(DWORD*)(FakeUnit(bald) + SC_CUNIT_OFF_SPRITE);
        *(DWORD*)(FakeUnit(bald) + SC_CUNIT_OFF_SPRITE) = 0;
        g_captureLen = 0; g_captureCount = 0;
        ScFanoutOnCommand(kRightClick, sizeof(kRightClick));
        Check("a unit with no sprite is in NO emitted Select",
              CaptureHasTag(baldTag, (int)sizeof(kRightClick)) ? 1 : 0, 0);
        Check("dropped as NOSPRITE", ScFanoutDroppedFor(SC_FANOUT_DROP_NOSPRITE), 1);
        *(DWORD*)(FakeUnit(bald) + SC_CUNIT_OFF_SPRITE) = sprite;
    }

    // ---------------------------------------------------------------------
    // The one place the gate WEAKENS an invariant, pinned so it cannot drift
    // further without a test noticing.
    //
    // "The visible chunk is emitted LAST, so the simulation ends up holding exactly
    // what the player sees" holds only while at least one visible unit is live. Kill
    // all twelve and that chunk emits nothing, so the simulation is left holding the
    // last OVERFLOW chunk. Narrow (all twelve inside the death window at once) and
    // self-healing on the next order, but it is real and the file's header comment now
    // says so -- this asserts the behaviour that comment describes.
    // ---------------------------------------------------------------------
    printf("\n    ALL 12 VISIBLE dead, overflow alive: the order still reaches the living\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        DriveSelection(36);
        for (int i = 0; i < 12; ++i) *(DWORD*)(FakeUnit(i) + SC_CUNIT_OFF_HITPOINTS) = 0;

        g_captureLen = 0; g_captureCount = 0;
        Check("suppressed: pairs did go out for the overflow",
              ScFanoutOnCommand(kRightClick, sizeof(kRightClick)) ? 1 : 0, 1);
        Check("the two overflow chunks are emitted, the visible one is not",
              g_captureCount, 4);
        Check("24 tags went out, none of them a visible unit",
              CaptureTagCount((int)sizeof(kRightClick)), 24);
        for (int i = 0; i < 12; ++i) {
            if (CaptureHasTag(ExpectTag(i), (int)sizeof(kRightClick))) {
                Check("a dead VISIBLE unit's tag reached the wire", 1, 0);
                break;
            }
        }
        Check("all 12 were charged to hp0", ScFanoutDroppedFor(SC_FANOUT_DROP_DEAD), 12);
        // THE WEAKENED INVARIANT, stated as the test sees it: the LAST Select of the
        // run is an overflow chunk, not the visible one, so the simulation is left
        // holding units the player cannot see. Asserted rather than hidden.
        Check("the last Select carries the SECOND overflow chunk (units 25-36), which "
              "is the invariant this case weakens",
              CaptureHasTag(ExpectTag(35), (int)sizeof(kRightClick)) ? 1 : 0, 1);
        for (int i = 0; i < 12; ++i) *(DWORD*)(FakeUnit(i) + SC_CUNIT_OFF_HITPOINTS) = 40 * 256;
    }

    printf("\n    a whole selection that died leaves the ENGINE's own order alone\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        DriveSelection(36);
        for (int i = 0; i < 36; ++i) *(DWORD*)(FakeUnit(i) + SC_CUNIT_OFF_HITPOINTS) = 0;
        g_captureLen = 0; g_captureCount = 0;
        // Not suppressed: with no live unit to select, suppressing the player's own
        // order would turn one click into nothing at all. StartFanout already had
        // this rule for an exhausted turn buffer; the gate must not break it.
        Check("not suppressed, so the engine's own order still goes out",
              ScFanoutOnCommand(kRightClick, sizeof(kRightClick)) ? 1 : 0, 0);
        Check("and no Select was emitted for a corpse",
              CaptureTagCount((int)sizeof(kRightClick)), 0);
        for (int i = 0; i < 36; ++i) *(DWORD*)(FakeUnit(i) + SC_CUNIT_OFF_HITPOINTS) = 40 * 256;
    }

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
    Part("the per-opcode policy: which commands reach all 36 units");

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
    Part("selection circles: fake sprites, fake engine primitives");

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

// A MODEL OF WHEN PIXELS LAND -- and it is a model; the engine is not in this process. It is
// here because the two facts task 048's fix rests on are both about TIMING and ORDER, and a
// primitive that only counts calls cannot exercise either:
//
//   * updateControl (0x0041C400) does NOT paint. It intersects the control's rect with the
//     dialog's and merges the result into the screen's dirty region. The paint is the dialog's
//     own redraw walk (0x0041C683), later -- which is why a copy of the band taken on the
//     frame that asks for a fill is a copy of the PREVIOUS layout;
//   * that walk takes the children from [dlg+0x42] and steps [esi], HEAD TO TAIL, so a control
//     earlier in the list is painted UNDER everything after it. At the head, this indicator
//     was painted first and the twelve wireframes painted over it, every frame.
//
// So FakeUpdateCtl accumulates a dirty box and FakePaint runs the walk, each visible control
// writing a byte derived from its own address so "who ended up on top" is decidable from the
// surface. WHAT THIS PROVES is the module's own bookkeeping: which frame each copy is taken
// on, and that the stranded count can fail. What the ENGINE draws is test-hud-row.ps1's job
// and nothing here substitutes for it.
static short g_dirty[4];
static bool  g_dirtyAny   = false;
static bool  g_paintOff   = false;     // the negative control below turns the repaint off

static void FakeUpdateCtl(DWORD ctrl) {
    ++g_ctlUpdates;
    const short* r = ScDlgBounds(ctrl);
    if (r[2] <= r[0] || r[3] <= r[1]) return;
    if (!g_dirtyAny) {
        g_dirty[0] = r[0]; g_dirty[1] = r[1]; g_dirty[2] = r[2]; g_dirty[3] = r[3];
        g_dirtyAny = true;
        return;
    }
    if (r[0] < g_dirty[0]) g_dirty[0] = r[0];
    if (r[1] < g_dirty[1]) g_dirty[1] = r[1];
    if (r[2] > g_dirty[2]) g_dirty[2] = r[2];
    if (r[3] > g_dirty[3]) g_dirty[3] = r[3];
}

static BYTE HudBackgroundAt(int off) { return (BYTE)(0x20 + (off % 7)); }
static BYTE HudPaintByte(DWORD ctrl) { return (BYTE)(0x80 | ((ctrl >> 4) & 0x3F)); }

static int __attribute__((fastcall)) FakeEngineInteract(DWORD ctrl, DWORD evt) {
    (void)ctrl; (void)evt;
    ++g_engInteractCalls;
    return 0;
}

static void FakeOrigDispatch(void) { ++g_origDispatchCalls; }

static DWORD FakeCtl(int i)      { return (DWORD)FakeRt(FAKE_DLG_VA) + 0x100u + (DWORD)i * SC_BINDLG_SIZE; }
static DWORD FakeStatUser(int i) { return (DWORD)FakeRt(FAKE_STATUSER_VA) + (DWORD)i * 8u; }
static DWORD FakeRoot(void)      { return (DWORD)FakeRt(FAKE_DLG_VA); }

// THE ROW'S REAL GEOMETRY, and the pane's, off the live dialog on this install -- the
// QINDDLG child dump in C:\sc-work\logs\039\group-fixed-production.log. It is here rather
// than in the module (where a constant would be a layout read off one install, AGENTS.md
// task 034) because the FAKE has to be a plausible pane or the placement it exercises is
// not the one the game gets. The twelve buttons are two rows of six, COLUMN-major -- ids
// 0x21/0x23/0x25/... on the upper row and 0x22/0x24/... on the lower -- which is why the
// row's lowest edge is 78 whether two units are selected or twelve.
#define HUD_SURF_W    270
#define HUD_SURF_H    92
#define HUD_BTN_LEFT  30
#define HUD_BTN_TOP   8
#define HUD_BTN_W     32
#define HUD_BTN_H     33
#define HUD_BTN_COL   36     // 30 -> 66 -> 102 ...
#define HUD_BTN_ROW   37     // upper 8..41, lower 45..78
#define HUD_ROW_BOTTOM (HUD_BTN_TOP + HUD_BTN_ROW + HUD_BTN_H)   // 78

static BYTE  g_hudSurf[HUD_SURF_W * HUD_SURF_H];
static BYTE  g_hudFont[16];
static short g_hudBox[4];      // the indicator's box on page 1, to compare across flips

// The redraw walk (see FakeUpdateCtl): repaint the dirty box with the background, then every
// VISIBLE child in list order, so the LAST one in the chain is the one left on the surface.
static void FakePaint(void) {
    if (!g_dirtyAny || g_paintOff) { g_dirtyAny = false; return; }
    int l = g_dirty[0] < 0 ? 0 : g_dirty[0];
    int t = g_dirty[1] < 0 ? 0 : g_dirty[1];
    int r = g_dirty[2] > HUD_SURF_W ? HUD_SURF_W : g_dirty[2];
    int b = g_dirty[3] > HUD_SURF_H ? HUD_SURF_H : g_dirty[3];
    for (int y = t; y < b; ++y) {
        for (int x = l; x < r; ++x) g_hudSurf[y * HUD_SURF_W + x] = HudBackgroundAt(y * HUD_SURF_W + x);
    }
    for (DWORD c = *(DWORD*)(FakeRoot() + SC_BINDLG_OFF_FIRST_CHILD); c;
         c = *(DWORD*)(c + SC_BINDLG_OFF_NEXT)) {
        if ((*(DWORD*)(c + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE) == 0) continue;
        const short* rc = ScDlgBounds(c);
        const BYTE v = HudPaintByte(c);
        const int y0 = rc[1] > t ? rc[1] : t, y1 = rc[3] < b ? rc[3] : b;
        const int x0 = rc[0] > l ? rc[0] : l, x1 = rc[2] < r ? rc[2] : r;
        for (int y = y0; y < y1; ++y) {
            for (int x = x0; x < x1; ++x) g_hudSurf[y * HUD_SURF_W + x] = v;
        }
    }
    g_dirtyAny = false;
}

// One whole frame the way the game runs one: the detour, then the redraw.
static void HudFrame(void) { ScHudRowOnDispatch(); FakePaint(); }

// Root dialog + one non-button control (id 1) + the 12 wireframe buttons
// (ids 0x21..0x2C), statUser records poisoned so "nobody wrote it" is
// distinguishable from "somebody wrote 0".
static void BuildFakeDialog(void) {
    const DWORD engineFn = (DWORD)FakeRt(SC_VA_WIREFRAME_BTN_INTERACT);
    DWORD root = FakeRoot();
    memset((void*)root, 0, SC_BINDLG_SIZE);
    *(WORD*)(root + SC_BINDLG_OFF_TYPE) = 0;                    // a dialog

    // The dialog's own 8-bit surface, at the offset the draw walk installs. Without one the
    // indicator has nowhere to be measured against and PlaceIndicator refuses outright --
    // which is the correct production behaviour and would make this whole part vacuous, so
    // the fake carries a real surface (the same thing part [19]'s pane does). It is filled
    // with a non-zero pattern on purpose: a zeroed surface would make an ink count and a
    // difference count agree, and the entire point of task 048 is that they do not.
    for (int i = 0; i < (int)sizeof(g_hudSurf); ++i) g_hudSurf[i] = HudBackgroundAt(i);
    g_dirtyAny = false;
    g_paintOff = false;
    *(WORD*) (root + SC_BINDLG_OFF_SURFACE + SC_SURFACE_OFF_W)    = HUD_SURF_W;
    *(WORD*) (root + SC_BINDLG_OFF_SURFACE + SC_SURFACE_OFF_H)    = HUD_SURF_H;
    *(DWORD*)(root + SC_BINDLG_OFF_SURFACE + SC_SURFACE_OFF_BITS) = (DWORD)&g_hudSurf[0];

    // The small font's header. 11 is what the live pane reports (`fontH=11` on every QIND
    // line), and the band this module places into is 13 rows tall -- so the margin the
    // engine's own draw rule needs (`top + fontHeight <= clip.bottom`) is two pixels, and a
    // regression that shrinks either number fails here rather than in front of a player.
    memset((void*)&g_hudFont[0], 0, sizeof(g_hudFont));
    g_hudFont[SC_FONT_OFF_HEIGHT] = 11;
    *(DWORD*)FakeRt(SC_VA_FONT_SMALLEST) = (DWORD)&g_hudFont[0];

    for (int i = 0; i < 13; ++i) {
        DWORD c = FakeCtl(i);
        memset((void*)c, 0, SC_BINDLG_SIZE);
        *(WORD*) (c + SC_BINDLG_OFF_TYPE)   = (i == 0) ? 5 : 2; // image, then buttons
        *(short*)(c + SC_BINDLG_OFF_INDEX)  = (i == 0) ? 1 : (short)(SC_HUD_FIRST_SMALL_BUTTON + i - 1);
        *(DWORD*)(c + SC_BINDLG_OFF_PARENT) = root;
        *(DWORD*)(c + SC_BINDLG_OFF_NEXT)   = (i < 12) ? FakeCtl(i + 1) : 0;
        short* b = ScDlgBounds(c);
        const int slot = (i == 0) ? 0 : i - 1;                  // ctl 0 is the image
        b[0] = (short)(HUD_BTN_LEFT + (slot / 2) * HUD_BTN_COL);
        b[1] = (short)(HUD_BTN_TOP  + (slot % 2) * HUD_BTN_ROW);
        b[2] = (short)(b[0] + HUD_BTN_W);
        b[3] = (short)(b[1] + HUD_BTN_H);
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

// The indicator, found by walking the LIVE child chain for its own negative id -- never by
// assuming which END of the list it sits on. That assumption is exactly what task 048 had to
// change (head -> tail), and a test that hardcodes it reports the assumption rather than the
// truth.
static DWORD HudIndicator(void) {
    for (DWORD c = *(DWORD*)(FakeRoot() + SC_BINDLG_OFF_FIRST_CHILD); c;
         c = *(DWORD*)(c + SC_BINDLG_OFF_NEXT)) {
        if (*(short*)(c + SC_BINDLG_OFF_INDEX) == (short)0xFFE0) return c;
    }
    return 0;
}

// Is it the LAST child? Not decoration: the dialog's redraw walk (0x0041C683) takes the
// children head to tail, so a control EARLIER in the list is painted UNDER everything after
// it. At the head, this indicator was painted first and the twelve wireframes painted over
// it -- which is why it was never seen in a game.
static int HudIndicatorIsLast(void) {
    DWORD ind = HudIndicator();
    return (ind && *(DWORD*)(ind + SC_BINDLG_OFF_NEXT) == 0) ? 1 : 0;
}

static const char* HudIndicatorText(void) {
    DWORD ind = HudIndicator();
    return ind ? (const char*)*(DWORD*)(ind + SC_BINDLG_OFF_TEXT) : NULL;
}

// Entering paged mode, the band's clean copy has to be taken on a frame that FOLLOWS the one
// asking for the fill -- it must be a copy of the pane THIS page draws, and updateControl only
// dirties (IndicatorFrame). So a test that wants to read the TEXT drives frames until the line
// is up rather than assuming one dispatch is enough. Bounded: a module that never shows it
// fails the next assertion instead of hanging here.
static void HudDispatchUntilShown(int maxFrames) {
    for (int i = 0; i < maxFrames && !ScHudRowIndicatorShowing(); ++i) ScHudRowOnDispatch();
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
// the click gate's ScUnitInOwnPlayerList walk runs for real. Head-insert.
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

// ---------------------------------------------------------------------------
// [11] Shadow control groups (task 021), driven the same way as [7].
//
// The feature has no hook and no engine call: it is entirely a reaction to wire
// command 0x13 arriving at ScFanoutOnCommand, plus TWO READS of engine memory --
// activePlayerSelection (0x006284B8), which the engine's client-side recall has
// already filled by then, and selectionHotkeys (0x0057FE60), which it reads only to
// notice that the engine has restarted a game underneath it. Both live inside the fake
// 3 MB image, so the whole state machine drives offline with no StarCraft in the
// process and every emitted byte still asserted on the wire.
//
// What stays untestable here is the ONE runtime claim the design rests on -- that the
// engine really has filled activePlayerSelection by the time it queues `13 01 g`. That
// is what test-control-groups.ps1 checks in the live game, off the plugin's own
// `GROUP recall enter:` read-back.
// ---------------------------------------------------------------------------

// The engine's own control-group row, as CMDRECV_Hotkey's store would have left it:
// StoredUnit tags, not pointers.
static void FakeEngineHotkeyRow(int group, const int* idx, int n) {
    const BYTE player = *(BYTE*)FakeRt(SC_VA_ACTIVE_PLAYER_ID);
    DWORD* row = (DWORD*)FakeRt(SC_VA_SELECTION_HOTKEYS)
               + (size_t)(player * SC_HOTKEY_GROUPS_PER_PLAYER + group)
                 * SC_HOTKEY_SLOTS_PER_GROUP;
    for (int i = 0; i < SC_HOTKEY_SLOTS_PER_GROUP; ++i) row[i] = 0;
    for (int i = 0; i < n && i < SC_HOTKEY_SLOTS_PER_GROUP; ++i) row[i] = ExpectTag(idx[i]);
}

static void ZeroEngineHotkeys(void) {
    memset(FakeRt(SC_VA_SELECTION_HOTKEYS), 0,
           (size_t)SC_MAX_PLAYERS * SC_HOTKEY_GROUPS_PER_PLAYER
           * SC_HOTKEY_SLOTS_PER_GROUP * 4);
}

// activePlayerSelection as CreateNewUnitSelectionsFromList (0x0049AE40) leaves it:
// CUnit pointers, dense from slot 0, NULL-terminated.
static void FakeEngineVisible(const int* idx, int n) {
    DWORD* arr = (DWORD*)FakeRt(SC_VA_ACTIVE_PLAYER_SELECTION);
    for (int i = 0; i < SC_SELECTION_SLOTS; ++i) arr[i] = 0;
    for (int i = 0; i < n && i < SC_SELECTION_SLOTS; ++i) arr[i] = FakeUnit(idx[i]);
}

// The three-byte 0x13 the engine builds at 0x004C07BF.
static bool Hotkey(BYTE action, BYTE group) {
    const BYTE cmd[SC_HOTKEY_CMD_BYTES] = { SC_CMD_HOTKEY, action, group };
    return ScFanoutOnCommand(cmd, sizeof(cmd));
}

// units 0..11 are the engine's twelve in every case below.
static const int kFirstTwelve[12] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };

static void ControlGroupTests(void) {
    Part("shadow control groups: Ctrl+N over 12, and N brings them back");

    g_fake = (BYTE*)VirtualAlloc(NULL, FAKE_IMAGE_BYTES, MEM_COMMIT | MEM_RESERVE,
                                 PAGE_READWRITE);
    if (!g_fake) { printf("  FAIL could not allocate the fake image\n"); ++g_failures; return; }

    MakeUnits(64, 1);
    // All three player-id globals set to the units' owner, so the row this code indexes
    // is the row the engine's own store would write and DisagreeingPlayerIds is quiet.
    *(BYTE*)FakeRt(SC_VA_ACTIVE_PLAYER_ID) = 1;
    *(BYTE*)FakeRt(SC_VA_PLAYER_ID_512688) = 1;
    *(BYTE*)FakeRt(SC_VA_PLAYER_ID_512678) = 1;

    printf("\n    Ctrl+1 on 36 units stores 36, and 1 brings all 36 back\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        ZeroEngineHotkeys();
        DriveSelection(36);
        Check("the shadow list holds the whole box", ScFanoutShadowCount(), 36);
        Check("  the engine holds only twelve of them", ScFanoutVisibleCount(), 12);

        g_captureLen = 0; g_captureCount = 0;
        Check("Ctrl+1 is NOT suppressed -- the engine's own 0x13 still goes out",
              Hotkey(SC_HOTKEY_ASSIGN, 1) ? 1 : 0, 0);
        Check("  and we emitted nothing of our own for it", g_captureCount, 0);
        Check("plugin group 1 holds all 36", ScFanoutGroupCount(1), 36);
        Check("  one assign counted", ScFanoutGroupStat(SC_FANOUT_GROUP_ASSIGN), 1);

        // The engine now executes that store: its own group holds its twelve.
        FakeEngineHotkeyRow(1, kFirstTwelve, 12);

        // The player selects something else entirely -- one unit, the way a click does.
        {
            DWORD one[1] = { FakeUnit(40) };
            ScFanoutOnSelect(1, one);
        }
        Check("after clicking away the shadow list is just that one unit",
              ScFanoutShadowCount(), 1);

        // Press 1. The engine's client handler has already run 0x0049AE40, so
        // activePlayerSelection holds its twelve before our hook sees the command.
        FakeEngineVisible(kFirstTwelve, 12);
        g_captureLen = 0; g_captureCount = 0;
        Check("the recall is NOT suppressed either", Hotkey(SC_HOTKEY_RECALL, 1) ? 1 : 0, 0);
        // Conductor's point (3a): a recall must not itself be a burst of replayed
        // Selects. It emits NOTHING -- the replay only ever happens when the player next
        // issues a fanned order, exactly as before this task.
        Check("  a recall emits no Select of its own", g_captureCount, 0);

        Check("ALL 36 ARE BACK", ScFanoutShadowCount(), 36);
        Check("  the engine still holds only twelve", ScFanoutVisibleCount(), 12);
        Check("  counted as a >12 recall", ScFanoutGroupStat(SC_FANOUT_GROUP_WIDE), 1);
        Check("  nothing was discarded", ScFanoutGroupStat(SC_FANOUT_GROUP_DISCARD), 0);

        // ... and the order that follows reaches every one of them, on the wire.
        g_captureLen = 0; g_captureCount = 0;
        Check("the next order is fanned out",
              ScFanoutOnCommand(kRightClick, sizeof(kRightClick)) ? 1 : 0, 1);
        Check("  3 Select+order pairs", g_captureCount, 6);
        Check("  36 tags on the wire", CaptureTagCount((int)sizeof(kRightClick)), 36);
        int missing = 0;
        for (int i = 0; i < 36; ++i) {
            if (!CaptureHasTag(ExpectTag(i), (int)sizeof(kRightClick))) ++missing;
        }
        Check("  and every one of the 36 units is among them", missing, 0);
        // The exact wire stream, chunk by chunk. The group was stored in shadow order
        // (overflow 12..35, then visible 0..11), so a recall reproduces the same chunking
        // part [7] asserts for a fresh drag box -- and crucially the VISIBLE chunk is
        // still LAST, which is the invariant that leaves the simulation holding what the
        // player can see. A recall must not quietly break it.
        {
            int a[SC_SELECTION_SLOTS], b[SC_SELECTION_SLOTS], v[SC_SELECTION_SLOTS];
            for (int i = 0; i < SC_SELECTION_SLOTS; ++i) {
                a[i] = 12 + i; b[i] = 24 + i; v[i] = i;
            }
            int off = 0;
            off = ExpectSelectAt("  pair 1 selects the restored units 13-24", off, a, 12);
            off = ExpectOrderAt ("  pair 1 carries the order verbatim", off);
            off = ExpectSelectAt("  pair 2 selects the restored units 25-36", off, b, 12);
            off = ExpectOrderAt ("  pair 2 carries the order verbatim", off);
            off = ExpectSelectAt("  pair 3 selects the VISIBLE 12 (last)", off, v, 12);
            (void)ExpectOrderAt ("  pair 3 carries the order verbatim", off);
        }
    }

    printf("\n    a unit in a >12 group DIES: recall returns the survivors, never the corpse\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        ZeroEngineHotkeys();
        DriveSelection(36);
        Hotkey(SC_HOTKEY_ASSIGN, 2);
        Check("group 2 holds 36", ScFanoutGroupCount(2), 36);
        FakeEngineHotkeyRow(2, kFirstTwelve, 12);

        // Kill one unit that is PAST the cap -- the engine's own group never knew about
        // it, so only our group can resurrect it. Damage death: hitpoints 0, uniqueness
        // deliberately untouched, which is precisely what CUnit+0xA5 cannot see.
        const int corpse = 20;
        const BYTE uniqBefore = *(BYTE*)(FakeUnit(corpse) + SC_CUNIT_OFF_UNIQUENESS);
        *(DWORD*)(FakeUnit(corpse) + SC_CUNIT_OFF_HITPOINTS) = 0;
        Check("the corpse's uniqueness byte is UNCHANGED (the case 0xA5 cannot see)",
              *(BYTE*)(FakeUnit(corpse) + SC_CUNIT_OFF_UNIQUENESS), uniqBefore);

        { DWORD one[1] = { FakeUnit(40) }; ScFanoutOnSelect(1, one); }
        FakeEngineVisible(kFirstTwelve, 12);
        Hotkey(SC_HOTKEY_RECALL, 2);

        Check("35 come back, not 36", ScFanoutShadowCount(), 35);
        Check("  and the group itself is compacted to 35", ScFanoutGroupCount(2), 35);

        g_captureLen = 0; g_captureCount = 0;
        ScFanoutOnCommand(kRightClick, sizeof(kRightClick));
        Check("the dead unit's tag is in NO emitted Select",
              CaptureHasTag(ExpectTag(corpse), (int)sizeof(kRightClick)) ? 1 : 0, 0);
        Check("  35 tags went out", CaptureTagCount((int)sizeof(kRightClick)), 35);
        *(DWORD*)(FakeUnit(corpse) + SC_CUNIT_OFF_HITPOINTS) = 40 * 256;
    }

    printf("\n    a REMOVED unit (trigger RemoveUnit / archon) is not resurrected either\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        ZeroEngineHotkeys();
        DriveSelection(36);
        Hotkey(SC_HOTKEY_ASSIGN, 3);
        FakeEngineHotkeyRow(3, kFirstTwelve, 12);

        const int gone = 25;
        const BYTE uniqBefore = *(BYTE*)(FakeUnit(gone) + SC_CUNIT_OFF_UNIQUENESS);
        const DWORD hpBefore  = *(DWORD*)(FakeUnit(gone) + SC_CUNIT_OFF_HITPOINTS);
        UnlinkFakeUnit(gone, 1);
        Check("hit points untouched by the removal",
              (int)*(DWORD*)(FakeUnit(gone) + SC_CUNIT_OFF_HITPOINTS), (int)hpBefore);
        Check("uniqueness untouched by the removal",
              *(BYTE*)(FakeUnit(gone) + SC_CUNIT_OFF_UNIQUENESS), uniqBefore);

        { DWORD one[1] = { FakeUnit(40) }; ScFanoutOnSelect(1, one); }
        FakeEngineVisible(kFirstTwelve, 12);
        Hotkey(SC_HOTKEY_RECALL, 3);
        Check("35 come back", ScFanoutShadowCount(), 35);
        RelinkFakeUnit(gone, 1);
    }

    printf("\n    CONTAINMENT: a group that does not describe this selection is discarded\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        ZeroEngineHotkeys();
        DriveSelection(36);
        Hotkey(SC_HOTKEY_ASSIGN, 4);
        Check("group 4 holds 36", ScFanoutGroupCount(4), 36);
        FakeEngineHotkeyRow(4, kFirstTwelve, 12);

        // The engine recalls TWELVE UNITS WE NEVER STORED -- the shape a group left over
        // from a previous game has. Falling back to the engine's own twelve is the only
        // safe reading; silently unioning would put a previous game's units on the wire.
        const int others[12] = { 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51 };
        { DWORD one[1] = { FakeUnit(40) }; ScFanoutOnSelect(1, one); }
        FakeEngineVisible(others, 12);
        Hotkey(SC_HOTKEY_RECALL, 4);

        Check("the shadow list is the engine's twelve and nothing more",
              ScFanoutShadowCount(), 12);
        Check("  one discard counted", ScFanoutGroupStat(SC_FANOUT_GROUP_DISCARD), 1);
        Check("  and the poisoned group is forgotten", ScFanoutGroupCount(4), -1);
    }

    printf("\n    NEW GAME: the engine's groups are cleared under us, so ours go too\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        ZeroEngineHotkeys();
        DriveSelection(36);
        Hotkey(SC_HOTKEY_ASSIGN, 5);
        Check("group 5 holds 36", ScFanoutGroupCount(5), 36);

        // The engine executes the store, so its row is filled. A shift-add now must
        // KEEP the group -- this is the case the reset must not fire on.
        FakeEngineHotkeyRow(5, kFirstTwelve, 12);
        Hotkey(SC_HOTKEY_ADD, 5);
        Check("a shift-add with the row filled keeps the group", ScFanoutGroupCount(5), 36);
        Check("  no reset counted", ScFanoutGroupStat(SC_FANOUT_GROUP_RESET), 0);

        // Now a new game: 0x004EEC30 zeroes the whole array.
        ZeroEngineHotkeys();
        { DWORD fresh[1] = { FakeUnit(50) }; ScFanoutOnSelect(1, fresh); }
        Hotkey(SC_HOTKEY_ADD, 5);
        Check("the stale group was dropped, so the add behaves as an assign",
              ScFanoutGroupCount(5), 1);
        Check("  a reset was counted", ScFanoutGroupStat(SC_FANOUT_GROUP_RESET) > 0 ? 1 : 0, 1);
    }

    // -----------------------------------------------------------------------
    // THE CASE THAT USED TO SHIP BROKEN, AND THE ONE THE OLD TEST COULD NOT SEE.
    //
    // Review found that the first version of the reset kept a per-group "I have
    // observed the engine's row filled" flag and only reset when that flag was set. The
    // store is RECEIVE-SIDE, so on a FIRST Ctrl+N the row is still empty at that
    // instant and the flag was never recorded -- which made a group used exactly once
    // permanently immune to the reset. That is ordinary play, not a corner: assign a
    // group, never touch it again, start a new mission, shift-add into it.
    //
    // The block above could not catch it, because it issues an extra shift-add WITH the
    // row filled before the new game, which is what set the flag. This block is the
    // sequence with no such command in it, and it is why the mechanism is now the
    // engine-mirroring rule (an add into an empty row is an assign) with no memory at
    // all. Deleting that rule fails HERE.
    // -----------------------------------------------------------------------
    printf("\n    NEW GAME after a group used exactly ONCE (the shipped-broken case)\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        ZeroEngineHotkeys();
        DriveSelection(36);
        Hotkey(SC_HOTKEY_ASSIGN, 8);              // the ONLY 0x13 of "game A"
        Check("group 8 holds 36", ScFanoutGroupCount(8), 36);
        // The engine executes that store some frames later...
        FakeEngineHotkeyRow(8, kFirstTwelve, 12);
        // ...and the player never touches group 8 again. New game: the array is zeroed.
        ZeroEngineHotkeys();
        {
            DWORD fresh[5];
            for (int i = 0; i < 5; ++i) fresh[i] = FakeUnit(40 + i);
            ScFanoutOnSelect(5, fresh);
        }
        Hotkey(SC_HOTKEY_ADD, 8);
        // Was 25 (36 of game A's records unioned with the new 5) before the fix.
        Check("the previous game's 36 are gone; the add holds only the new 5",
              ScFanoutGroupCount(8), 5);
        Check("  and a reset was counted", ScFanoutGroupStat(SC_FANOUT_GROUP_RESET) > 0 ? 1 : 0, 1);
    }

    // -----------------------------------------------------------------------
    // IDENTITY IS THE (POINTER, UNIQUENESS) PAIR, NOT THE POINTER.
    //
    // Also from review. A CUnit* is a slot in a fixed global that the engine reuses
    // game after game, so a stale record whose slot now holds a DIFFERENT live unit
    // must not read as "contained". The containment gate is the cross-session staleness
    // detector, and comparing bare pointers would make it pass on exactly the input it
    // exists to catch. The NEW-GAME containment case earlier in this part uses disjoint
    // slots (40..51 against a group of 0..35), which is the one shape where comparing
    // pointers and comparing pairs agree -- so it could not see this either.
    // -----------------------------------------------------------------------
    printf("\n    CONTAINMENT compares (pointer, uniqueness), not the pointer alone\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        ZeroEngineHotkeys();
        DriveSelection(36);
        Hotkey(SC_HOTKEY_ASSIGN, 9);
        Check("group 9 holds 36", ScFanoutGroupCount(9), 36);
        FakeEngineHotkeyRow(9, kFirstTwelve, 12);

        // Every slot the engine is about to recall is RECYCLED into a different unit --
        // the same addresses, new uniqueness bytes, exactly what a second game does to
        // the same 1700-entry array. Bare-pointer containment would call this contained
        // and hand the player a group built from the previous game's records.
        for (int i = 0; i < SC_SELECTION_SLOTS; ++i) {
            BYTE* u = (BYTE*)FakeUnit(i);
            u[SC_CUNIT_OFF_UNIQUENESS] = (BYTE)(u[SC_CUNIT_OFF_UNIQUENESS] + 1);
        }
        { DWORD one[1] = { FakeUnit(40) }; ScFanoutOnSelect(1, one); }
        FakeEngineVisible(kFirstTwelve, 12);
        Hotkey(SC_HOTKEY_RECALL, 9);

        Check("the recycled slots are NOT contained, so the group is discarded",
              ScFanoutGroupStat(SC_FANOUT_GROUP_DISCARD), 1);
        Check("  and the shadow list is the engine's twelve alone",
              ScFanoutShadowCount(), 12);
        Check("  the poisoned group is forgotten", ScFanoutGroupCount(9), -1);
        for (int i = 0; i < SC_SELECTION_SLOTS; ++i) {   // put the fixture back
            BYTE* u = (BYTE*)FakeUnit(i);
            u[SC_CUNIT_OFF_UNIQUENESS] = (BYTE)(u[SC_CUNIT_OFF_UNIQUENESS] - 1);
        }
    }

    printf("\n    shift-add UNIONS a second selection into the group\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        ZeroEngineHotkeys();
        DriveSelection(20);                       // units 0..19
        Hotkey(SC_HOTKEY_ASSIGN, 6);
        Check("group 6 holds the first 20", ScFanoutGroupCount(6), 20);
        FakeEngineHotkeyRow(6, kFirstTwelve, 12);

        // A second, overlapping selection: units 12..31.
        {
            DWORD visible[SC_SELECTION_SLOTS];
            for (int i = 0; i < SC_SELECTION_SLOTS; ++i) visible[i] = FakeUnit(12 + i);
            for (int i = SC_SELECTION_SLOTS; i < 20; ++i) {
                ScFanoutOnOverflow(SC_SELECTION_SLOTS, visible, FakeUnit(12 + i));
            }
            ScFanoutOnSelect(SC_SELECTION_SLOTS, visible);
        }
        Hotkey(SC_HOTKEY_ADD, 6);
        // 0..19 plus 12..31 = 0..31, deduplicated.
        Check("the union is 32 units, not 40", ScFanoutGroupCount(6), 32);
        Check("  one add counted", ScFanoutGroupStat(SC_FANOUT_GROUP_ADD), 1);
    }

    printf("\n    a 0x13 we do not understand falls back to the pre-021 behaviour\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        ZeroEngineHotkeys();
        DriveSelection(36);
        // Group 12 is one of the engine's OWN recent-selection groups (10..17), which we
        // deliberately do not mirror. The over-cap part of the list is dropped rather
        // than fanned out against a selection the engine rebuilt elsewhere.
        Hotkey(SC_HOTKEY_RECALL, 12);
        Check("the over-cap units are dropped, as before task 021",
              ScFanoutShadowCount(), 12);
        Check("  and no group was touched", ScFanoutGroupStat(SC_FANOUT_GROUP_RECALL), 0);

        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        DriveSelection(36);
        const BYTE truncated[2] = { SC_CMD_HOTKEY, SC_HOTKEY_RECALL };
        ScFanoutOnCommand(truncated, sizeof(truncated));
        Check("a wrong-length 0x13 does the same", ScFanoutShadowCount(), 12);
    }

    printf("\n    a unit that is already dead never ENTERS a group\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        ZeroEngineHotkeys();
        DriveSelection(36);
        *(DWORD*)(FakeUnit(30) + SC_CUNIT_OFF_HITPOINTS) = 0;
        Hotkey(SC_HOTKEY_ASSIGN, 7);
        Check("the group holds 35, not 36", ScFanoutGroupCount(7), 35);
        *(DWORD*)(FakeUnit(30) + SC_CUNIT_OFF_HITPOINTS) = 40 * 256;
    }

    ScFanoutTestBegin(NULL, NULL, 200);   // leave the core inert
    VirtualFree(g_fake, 0, MEM_RELEASE);
    g_fake = NULL;
}

static void HudRowTests(void) {
    Part("HUD-row paging: fake dialog tree, fake engine primitives");

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
    // No engine, no real clock between these frames, and a paint model that runs
    // synchronously inside HudFrame -- so the module's wall-clock settle windows would be
    // measuring this harness. Zero them; the ORDER they enforce still runs (see the header).
    ScHudRowTestSetBandTiming(0, 0);

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
    HudDispatchUntilShown(4);
    {
        DWORD ind = HudIndicator();
        Check("  found in the chain by its own negative id", ind ? 1 : 0, 1);
        Check("  at the TAIL, so the redraw walk paints it LAST -- over the wireframes, not "
              "under them (task 048)", HudIndicatorIsLast(), 1);
        Check("  interact from the type-9 default table",
              (long long)*(DWORD*)(ind + SC_BINDLG_OFF_INTERACT), 0x11111111);
        Check("  update from the type-9 default table",
              (long long)*(DWORD*)(ind + SC_BINDLG_OFF_UPDATE), 0x22222222);
        const char* text = HudIndicatorText();
        Check("  text says 36 units, 1-12, page 1/3",
              (text && strstr(text, "36 units") && strstr(text, "1-12") &&
               strstr(text, "(1/3)")) ? 1 : 0, 1);

        // TASK 048: WHERE IT IS. The box used to start one pixel below the first button's own
        // top -- inside the icon row, across the wireframes -- which is the placement the user
        // reported for task 039's group line and which this indicator still carried. It now
        // goes in the band below the row, and "outside the row" is asserted as a NUMBER
        // against the row's own lowest edge rather than against a remembered constant.
        short box[4];
        ScHudRowIndicatorBox(box);
        int rowBottom = 0, rowLeft = 0x7FFF;
        for (int i = 1; i <= 12; ++i) {
            short* b = ScDlgBounds(FakeCtl(i));
            if (b[3] > rowBottom) rowBottom = b[3];
            if (b[0] < rowLeft)   rowLeft   = b[0];
        }
        Check("  the row's lowest button edge is where the dump says (78)",
              (long long)rowBottom, (long long)HUD_ROW_BOTTOM);
        Check("  and the line starts BELOW all twelve of them", box[1] >= rowBottom ? 1 : 0, 1);
        Check("  flush with the row's left edge", (long long)box[0], (long long)rowLeft);
        Check("  it stays inside the dialog's own surface",
              (box[2] <= HUD_SURF_W && box[3] <= HUD_SURF_H) ? 1 : 0, 1);
        // The engine's string draw refuses OUTRIGHT when top + fontHeight > clip.bottom, and
        // the clip box is these bounds -- the defect that made task 033's indicator invisible.
        Check("  and is at least as tall as the font says it must be (fontH=11)",
              (box[3] - box[1]) >= 11 ? 1 : 0, 1);
        // A box too NARROW does not fail loudly, it draws a TRUNCATION, which reads as a
        // working feature. The width is reserved for the LONGEST line this selection can
        // produce ("36 units  25-36  (3/3)"), not the one showing, so a page flip cannot move
        // the right edge -- and a box that moved would throw its baseline away every flip.
        Check("  wide enough for the longest line this selection can produce",
              (box[2] - box[0]) >= (int)strlen("36 units  25-36  (3/3)") * 5 ? 1 : 0, 1);
        g_hudBox[0] = box[0]; g_hudBox[1] = box[1];
        g_hudBox[2] = box[2]; g_hudBox[3] = box[3];
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
            const char* text = HudIndicatorText();
            Check("  indicator says 13-24 (2/3)",
                  (text && strstr(text, "13-24") && strstr(text, "(2/3)")) ? 1 : 0, 1);
            // AND THE BOX DID NOT MOVE. "1-12" and "13-24" are different lengths, so a box
            // sized to the CURRENT string would grow here -- and a box that has moved has no
            // baseline, so the screen-level oracle would answer "no answer" on exactly the
            // flip it exists to measure. It is sized for the longest line the selection can
            // produce instead.
            short box[4];
            ScHudRowIndicatorBox(box);
            Check("  and the box is byte-identical across the flip",
                  (box[0] == g_hudBox[0] && box[1] == g_hudBox[1] &&
                   box[2] == g_hudBox[2] && box[3] == g_hudBox[3]) ? 1 : 0, 1);
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
            const char* text = HudIndicatorText();
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
            const char* text = HudIndicatorText();
            Check("  indicator says 35 units (only unit 16 dropped)",
                  (text && strstr(text, "35 units")) ? 1 : 0, 1);
        }
        *(BYTE*)(FakeUnit(16) + SC_CUNIT_OFF_UNIQUENESS) -= 1;
    }

    printf("\n    VISIBLE units dying re-flow the row; they do NOT hand it back to stock\n");
    // Task 033, from the user playing the deployed build: "when i have more than 12 units
    // selected and some die - the group display in tug doesn't get updated (i might have 30
    // units selected but the group shows 6 cuz 6 of the ones from tug died)".
    //
    // The skew this reproduces: the engine zeroes hitPoints in its damage primitive
    // (0x004797B0) and clears the unit out of clientSelectionGroup on a LATER path, so for
    // at least one frame our liveness test says "dead" while the engine's own selection
    // still lists it. Counting a LIVE-FILTERED tail against an UNFILTERED engine list makes
    // that ordinary skew look like an engine-side REMOVAL -- and the divergence latch is
    // permanent until the next commit, so one frame of it stranded the row on stock for the
    // rest of the selection, showing only the survivors of the engine's twelve.
    //
    // clientSelectionGroup is deliberately NOT updated here. That IS the case.
    {
        Drive36Sync();
        ScHudRowOnDispatch();
        Check("paged before the deaths", ScHudRowPageCount(), 3);
        for (int i = 0; i < 6; ++i) *(DWORD*)(FakeUnit(i) + SC_CUNIT_OFF_HITPOINTS) = 0;
        ResetHudCounters();
        ScHudRowOnDispatch();
        Check("  the row did NOT hand back to stock", (long long)g_origDispatchCalls, 0);
        Check("  did NOT latch diverged", ScHudRowIsDiverged() ? 1 : 0, 0);
        Check("  30 live units -> still 3 pages", ScHudRowPageCount(), 3);
        Check("  snapped back to page 1", ScHudRowCurrentPage() + 1, 1);
        {
            int shown = 0; bool allLive = true;
            for (int i = 0; i < 12; ++i) {
                if (!(*(DWORD*)(FakeCtl(1 + i) + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE))
                    continue;
                ++shown;
                DWORD u = ShownStatUserUnit(i);
                if (!u || *(DWORD*)(u + SC_CUNIT_OFF_HITPOINTS) == 0) allLive = false;
            }
            Check("  the row is FULL again: 12 slots shown", shown, 12);
            Check("  and every displayed unit is ALIVE", allLive ? 1 : 0, 1);
        }
        {
            // ... and when the engine's own removal path catches up a frame later and drops
            // the six, nothing changes: the same twelve live units stay on the row.
            DWORD survivors[12];
            for (int i = 0; i < 6; ++i) survivors[i] = FakeUnit(6 + i);
            SetEngineSelection(survivors, 6);
            ResetHudCounters();
            ScHudRowOnDispatch();
            Check("  engine catching up does not diverge either",
                  ScHudRowIsDiverged() ? 1 : 0, 0);
            Check("  and still does not hand back to stock", (long long)g_origDispatchCalls, 0);
        }
        for (int i = 0; i < 6; ++i) *(DWORD*)(FakeUnit(i) + SC_CUNIT_OFF_HITPOINTS) = 40 * 256;
        SetEngineSelectionFirst(12);
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
    // The exposure (b) closes: an overflow unit REMOVED FROM PLAY (trigger RemoveUnit
    // / archon-consumed -- i.e. unlinked from its player unit list) keeps HP and
    // uniqueness and is NOT in clientSelectionGroup, so the divergence check cannot
    // see it. UnlinkFakeUnit models exactly that removal. A click on its portrait must
    // be swallowed before the engine's Select sees the stale pointer. (A transport-
    // loaded or mind-controlled unit stays list-linked and would correctly PASS -- it
    // is a live, identity-correct CUnit*.)
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
    // The hand-back asks the engine to repaint what the indicator was covering. That used to
    // be the twelve buttons alone and it was enough, because the box sat ON them. Now the box
    // is in a band NO control occupies, so UnspliceIndicator asks for OUR OWN rect too --
    // updateControl on the hidden control -- and without that ask nothing would ever repaint
    // there. The count below is the weak form of that; the stranded measurement further down
    // is the strong one.
    Check("the hand-back asked for a repaint (band + row)", g_ctlUpdates > 0 ? 1 : 0, 1);
    ResetHudCounters();
    ScHudRowOnDispatch();
    Check("and it stays stock (engine dispatcher keeps running)",
          (long long)g_origDispatchCalls, 1);

    printf("\n    re-entering overflow re-wraps and re-splices exactly once\n");
    Drive36Sync();
    ScHudRowOnDispatch();
    ScHudRowOnDispatch();                     // idempotence: a second frame changes nothing
    Check("still 14 children after two frames", CountChildren(), 14);

    printf("\n    task 048: our line goes ON the band, and comes OFF it again\n");
    // Everything from here on runs the frames through HudFrame -- detour, then redraw walk --
    // so the surface actually changes and the module's two screen-level readings have
    // something to read. See FakeUpdateCtl for what is being modelled and what is not.
    {
        SmallSync(1);
        HudFrame();                                     // stock, and a painted surface
        Drive36Sync();
        // The frames are driven ONE AT A TIME here rather than "until it is showing", because
        // WHICH frame each thing happens on is the whole point of this block.
        HudFrame();                                     // paged call 1: splice + place, nothing shown
        Check("  one paged call is deliberately NOT enough to show it",
              ScHudRowIndicatorShowing() ? 1 : 0, 0);
        // Then poll, WITHOUT painting in between, until the band has been read unchanged and
        // the clean copy is taken. Nothing repaints here, so this settles immediately -- in a
        // game it is a wall-clock window, because the walk can be tens of thousands of calls
        // away and a call count cannot stand in for it.
        int settleCalls = 0;
        while (!ScHudRowIndicatorShowing() && settleCalls < 8) {
            ScHudRowOnDispatch(); ++settleCalls;
        }
        Check("the line goes up once the band has been read unchanged",
              ScHudRowIndicatorShowing() ? 1 : 0, 1);

        // The show has only asked for a dirty region: the redraw walk has not run, so NOTHING
        // of ours is on the surface yet. That is the reading task 033's `ink` could never
        // give -- it read 2368 of 2368 here whatever the truth was.
        Check("  before the redraw walk, the band still matches its clean copy",
              (long long)ScHudRowBandDiff(), 0);
        FakePaint();                                    // the walk
        Check("  after it, the band differs from that copy -- the line IS on the surface",
              ScHudRowBandDiff() > 0 ? 1 : 0, 1);
        // ... and the paint that put it there is the LAST one in the walk. At the head of the
        // child list the buttons would have overwritten it, which is what a diff of 0 here
        // would mean and what the game was actually doing.
        Check("  and it was painted OVER, not under (the tail splice)",
              HudIndicatorIsLast(), 1);

        ScHudRowOnDispatch();                           // the module takes its inked copy
        int glyph = -1;
        Check("  the inked copy is taken once the band actually differs, never on the show",
              ScHudRowBandStranded(&glyph) >= 0 ? 1 : 0, 1);
        Check("  and the glyph mask is not empty", glyph > 0 ? 1 : 0, 1);

        // THE HAND-BACK. This is what the old placement bought for free and what moving into
        // an unowned band puts at risk, so it is measured rather than argued.
        SmallSync(1);
        HudFrame();                                     // RestoreStock: hide + ask; then paint
        ScHudRowOnDispatch();                           // the reading, on a LATER stock frame
        glyph = -1;
        int stranded = ScHudRowBandStranded(&glyph);
        Check("after the hand-back the probe still has a mask to check", glyph > 0 ? 1 : 0, 1);
        Check("  and NOTHING of our line survived it", (long long)stranded, 0);

        // THE NEGATIVE CONTROL, so that 0 is a result and not a property of the instrument.
        // Same sequence, with the model's redraw suppressed across the hand-back: nothing
        // repaints the band, every byte our line owns is still sitting there, and the count
        // has to say so. Without this, "stranded=0" and "the probe cannot see anything" are
        // the same reading (AGENTS.md: prove the pattern positive where it should match).
        Drive36Sync();
        for (int i = 0; i < 4 && !ScHudRowIndicatorShowing(); ++i) HudFrame();
        HudFrame();                                     // paint the line
        HudFrame();                                     // inked copy
        Check("the line is up again for the negative control",
              ScHudRowIndicatorShowing() ? 1 : 0, 1);
        g_paintOff = true;
        SmallSync(1);
        HudFrame();                                     // hand back, but NOTHING repaints
        ScHudRowOnDispatch();
        int glyph2 = -1;
        int stranded2 = ScHudRowBandStranded(&glyph2);
        g_paintOff = false;
        Check("with no repaint, every byte of the line is left stranded",
              (stranded2 > 0 && stranded2 == glyph2) ? 1 : 0, 1);
        Check("  so the check above can fail, and 0 was a result",
              (glyph2 > 0 && stranded2 != 0) ? 1 : 0, 1);
    }

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
// [13] Same-type building groups (task 024), driven the same way as [7].
//
// Two halves, both hook-free and both asserted here:
//
//   the CLIENT half -- ScFanoutGrowBuildingGroup, which turns SortAllUnits' one-building
//   fallback into the whole same-type group. Its inputs are exactly the engine's: the
//   NULL-terminated candidate list, the caller's 12-slot output array, the `clicked`
//   argument and the count the original returned.
//
//   the SIM half -- the chunk size. The simulation gate (addUnitToSelectionSlot
//   0x0049AF80) refuses a building every slot but the first, so the fan-out has to
//   deliver a building group ONE unit per Select, and that shows up here as the exact
//   wire stream: N x (Select(1) + order) instead of one Select(N).
//
// The engine's predicate (0x0047B770) is supplied as a stub -- a test process has no
// engine code, only a fake image -- and the stub answers by unit TYPE, which is what
// the real one does for a building (units.dat flag 0x01).
// ---------------------------------------------------------------------------

// Type ids: anything below 106 is an ordinary unit, 106+ a building. 106 is Terran
// Command Center and 109 Supply Depot in units.dat, which is also what the in-game
// fixture places -- the numbers are not load-bearing here, the SPLIT is.
#define FAKE_TYPE_MARINE  0
#define FAKE_TYPE_DEPOT   109
#define FAKE_TYPE_BARRACKS 111

static int __attribute__((fastcall)) FakeMovable(unsigned long unit) {
    return *(WORD*)(unit + SC_CUNIT_OFF_UNIT_ID) < 106 ? 1 : 0;
}

static void SetFakeType(int i, WORD type) {
    *(WORD*)(FakeUnit(i) + SC_CUNIT_OFF_UNIT_ID) = type;
}

// The units.dat prototype flags, in the fake image, agreeing with FakeMovable above.
//
// Task 036 made the plugin ask TWO questions where task 024 asked one -- "the predicate
// refused it" AND "units.dat says it is a building" -- because the predicate also refuses
// plenty of things that are not buildings, and a feature named building groups must not
// widen anything for those. The fake table has to carry the same split the stub does, or
// every case in this part would exercise the not-a-building branch and pass for the wrong
// reason. Called after every MakeUnits/ScFanoutTestBegin, since those reset the image.
static void SetFakeUnitsDatFlags(void) {
    DWORD* flags = (DWORD*)FakeRt(SC_VA_UNITS_DAT_FLAGS);
    for (int t = 0; t < 256; ++t) {
        flags[t] = (t >= 106) ? SC_UNITSDAT_FLAG_BUILDING : 0u;
    }
}

// The candidate list SortAllUnits is handed: CUnit pointers, NULL-terminated.
static void MakeCandidates(DWORD* buf, const int* idx, int n) {
    for (int i = 0; i < n; ++i) buf[i] = FakeUnit(idx[i]);
    buf[n] = 0;
}

static void BuildingGroupTests(void) {
    Part("same-type building groups: one box, N buildings, N rallies");

    // Its own fake image, like every other part: each one releases the previous one's.
    g_fake = (BYTE*)VirtualAlloc(NULL, FAKE_IMAGE_BYTES, MEM_COMMIT | MEM_RESERVE,
                                 PAGE_READWRITE);
    if (!g_fake) { printf("  FAIL could not allocate the fake image\n"); ++g_failures; return; }

    MakeUnits(64, 1);
    ResetQueueCounters();
    ScFanoutTestBegin(g_fake, &CaptureEmit, 400);
    ScFanoutTestSetMovable(&FakeMovable);
    SetFakeUnitsDatFlags();

    // 0..3 Supply Depots, 4..6 Barracks, 7..9 Marines. Same owner throughout; the
    // owner split gets its own case below.
    for (int i = 0; i < 4; ++i)  SetFakeType(i, FAKE_TYPE_DEPOT);
    for (int i = 4; i < 7; ++i)  SetFakeType(i, FAKE_TYPE_BARRACKS);
    for (int i = 7; i < 64; ++i) SetFakeType(i, FAKE_TYPE_MARINE);

    printf("\n    a box of four same-type buildings grows one into four\n");
    {
        DWORD cand[8];
        const int all[4] = { 0, 1, 2, 3 };
        MakeCandidates(cand, all, 4);
        DWORD out[SC_SELECTION_SLOTS] = { 0 };
        out[0] = FakeUnit(3);      // the engine's fallback: the LAST rejected candidate
        unsigned n = ScFanoutGrowBuildingGroup(cand, out, 0, 1);
        Check("the group is four", (int)n, 4);
        Check("the engine's own lead stays in slot 0", out[0] == FakeUnit(3) ? 1 : 0, 1);
        bool complete = true;
        for (int i = 0; i < 4; ++i) {
            bool found = false;
            for (unsigned j = 0; j < n; ++j) if (out[j] == FakeUnit(i)) found = true;
            if (!found) complete = false;
        }
        Check("all four depots are in the selection", complete ? 1 : 0, 1);
    }

    printf("\n    ... and a rally reaches every one of them, one Select per building\n");
    {
        DWORD sel[4] = { FakeUnit(3), FakeUnit(0), FakeUnit(1), FakeUnit(2) };
        ScFanoutOnSelect(4, sel);
        Check("the simulation holds ONE of them at a time", ScFanoutSimSlots(), 1);
        Check("the shadow list holds all four", ScFanoutShadowCount(), 4);

        g_captureLen = 0; g_captureCount = 0;
        bool suppressed = ScFanoutOnCommand(kRightClick, sizeof(kRightClick));
        Check("the engine's own right-click is suppressed", suppressed ? 1 : 0, 1);
        Check("4 pairs x (Select + order)", g_captureCount, 8);
        // 4 x (2 + 1*2) + 4 x 10 = 16 + 40 = 56
        Check("bytes queued", g_captureLen, 56);
        Check("every Select carries exactly one building", CaptureTagCount(10), 4);
        for (int i = 0; i < 4; ++i) {
            Check("  each building's tag reached the receive path",
                  CaptureHasTag(ExpectTag(i), 10) ? 1 : 0, 1);
        }
        // The visible chunk is emitted LAST here as everywhere else, and with slots=1
        // "the visible chunk" is the lead alone -- so the simulation ends up holding
        // the building the engine itself selected, which is what the player sees.
        int lead[1] = { 3 };
        (void)ExpectSelectAt("the LAST pair selects the engine's own lead",
                             g_captureLen - (2 + 2) - 10, lead, 1);
    }

    printf("\n    a MIXED-BUILDING box takes the type of the engine's own lead\n");
    {
        // Four depots and three barracks, no units. Vanilla picks one building; we keep
        // whichever one it picked and add that TYPE's siblings, so the outcome is
        // vanilla's choice widened, never a second arbitrary rule of ours.
        DWORD cand[12];
        const int mixed[7] = { 0, 1, 2, 3, 4, 5, 6 };
        MakeCandidates(cand, mixed, 7);

        DWORD out[SC_SELECTION_SLOTS] = { 0 };
        out[0] = FakeUnit(6);                    // the lead is a Barracks
        unsigned n = ScFanoutGrowBuildingGroup(cand, out, 0, 1);
        Check("a barracks lead selects the three barracks", (int)n, 3);
        bool onlyBarracks = true;
        for (unsigned j = 0; j < n; ++j) {
            if (*(WORD*)(out[j] + SC_CUNIT_OFF_UNIT_ID) != FAKE_TYPE_BARRACKS) onlyBarracks = false;
        }
        Check("  and no depot joined them", onlyBarracks ? 1 : 0, 1);

        DWORD out2[SC_SELECTION_SLOTS] = { 0 };
        out2[0] = FakeUnit(2);                   // same box, a depot lead
        unsigned n2 = ScFanoutGrowBuildingGroup(cand, out2, 0, 1);
        Check("a depot lead from the SAME box selects the four depots", (int)n2, 4);
    }

    printf("\n    a different owner is a different group\n");
    {
        *(BYTE*)(FakeUnit(1) + SC_CUNIT_OFF_PLAYER) = 2;   // one depot changes hands
        BuildFakePlayerList(64, 1);                        // ... and leaves player 1's list
        DWORD cand[8];
        const int all[4] = { 0, 1, 2, 3 };
        MakeCandidates(cand, all, 4);
        DWORD out[SC_SELECTION_SLOTS] = { 0 };
        out[0] = FakeUnit(3);
        unsigned n = ScFanoutGrowBuildingGroup(cand, out, 0, 1);
        Check("the other player's depot is not in the group", (int)n, 3);
        *(BYTE*)(FakeUnit(1) + SC_CUNIT_OFF_PLAYER) = 1;
        BuildFakePlayerList(64, 1);
    }

    printf("\n    task 020's liveness gate still decides who may join\n");
    {
        const DWORD hpWas = *(DWORD*)(FakeUnit(1) + SC_CUNIT_OFF_HITPOINTS);
        *(DWORD*)(FakeUnit(1) + SC_CUNIT_OFF_HITPOINTS) = 0;   // a damage death
        const int before = ScFanoutGroupRefusedFor(SC_FANOUT_DROP_DEAD);

        DWORD cand[8];
        const int all[4] = { 0, 1, 2, 3 };
        MakeCandidates(cand, all, 4);
        DWORD out[SC_SELECTION_SLOTS] = { 0 };
        out[0] = FakeUnit(3);
        unsigned n = ScFanoutGrowBuildingGroup(cand, out, 0, 1);
        Check("a destroyed building never enters the selection", (int)n, 3);
        Check("  and it was refused for being DEAD, not merely absent",
              ScFanoutGroupRefusedFor(SC_FANOUT_DROP_DEAD) - before, 1);
        bool none = true;
        for (unsigned j = 0; j < n; ++j) if (out[j] == FakeUnit(1)) none = false;
        Check("  the dead building's pointer is in no slot", none ? 1 : 0, 1);
        *(DWORD*)(FakeUnit(1) + SC_CUNIT_OFF_HITPOINTS) = hpWas;
    }

    printf("\n    more than twelve buildings: twelve visible, the rest past the cap\n");
    {
        for (int i = 0; i < 16; ++i) SetFakeType(i, FAKE_TYPE_DEPOT);
        MakeUnits(64, 1);                        // re-arm hp/sprites/list after the edits
        for (int i = 0; i < 16; ++i) SetFakeType(i, FAKE_TYPE_DEPOT);
        for (int i = 16; i < 64; ++i) SetFakeType(i, FAKE_TYPE_MARINE);
        ScFanoutTestBegin(g_fake, &CaptureEmit, 4000);
        ScFanoutTestSetMovable(&FakeMovable);
        SetFakeUnitsDatFlags();

        DWORD cand[20];
        int idx[16];
        for (int i = 0; i < 16; ++i) idx[i] = i;
        MakeCandidates(cand, idx, 16);
        DWORD out[SC_SELECTION_SLOTS] = { 0 };
        out[0] = FakeUnit(15);
        unsigned n = ScFanoutGrowBuildingGroup(cand, out, 0, 1);
        Check("the caller's twelve slots are filled and no more", (int)n, SC_SELECTION_SLOTS);

        ScFanoutOnSelect(n, out);
        Check("the shadow list holds all sixteen", ScFanoutShadowCount(), 16);
        Check("the engine holds twelve of them", ScFanoutVisibleCount(), SC_SELECTION_SLOTS);
        Check("the sim still holds ONE at a time", ScFanoutSimSlots(), 1);

        g_captureLen = 0; g_captureCount = 0;
        (void)ScFanoutOnCommand(kRightClick, sizeof(kRightClick));
        Check("16 pairs x (Select + order)", g_captureCount, 32);
        Check("every one of the sixteen is rallied", CaptureTagCount(10), 16);
        bool all16 = true;
        for (int i = 0; i < 16; ++i) if (!CaptureHasTag(ExpectTag(i), 10)) all16 = false;
        Check("  and each by its own tag", all16 ? 1 : 0, 1);
    }

    printf("\n    everything else is stock\n");
    {
        DWORD cand[8];
        const int all[4] = { 0, 1, 2, 3 };
        MakeCandidates(cand, all, 4);
        DWORD out[SC_SELECTION_SLOTS] = { 0 };
        out[0] = FakeUnit(3);

        // TASK 036 CHANGED THIS ONE, and it is left here rather than moved so the
        // reversal is visible next to what it reversed. Task 024 asserted that a
        // `clicked != 0` call was untouched, because it believed every click path passed
        // one. It does -- but only TWO click paths reach SortAllUnits at all, and both
        // are the ctrl-click / double-click "select all of this type on screen" branches
        // (sc_addresses.h SC_VA_CLICK_SELECT_HANDLER). A plain click and a shift-click
        // never call it. So the growth is now exactly as correct here as it is for a box.
        {
            DWORD cout[SC_SELECTION_SLOTS] = { 0 };
            cout[0] = FakeUnit(3);
            unsigned cn = ScFanoutGrowBuildingGroup(cand, cout, FakeUnit(3), 1);
            Check("a double-click / ctrl-click (clicked != 0) grows the same group", (int)cn, 4);
            Check("  and the CLICKED building is still the lead",
                  cout[0] == FakeUnit(3) ? 1 : 0, 1);
        }
        Check("a count other than 1 is untouched -- the engine found real units",
              (int)ScFanoutGrowBuildingGroup(cand, out, 0, 2), 2);

        // A MOVABLE lead is an ordinary unit the engine selected on its own merits, not
        // the one-building fallback, so the group logic must not fire at all. This is
        // also the stock arm for the whole feature: with every unit movable, the
        // function is the identity.
        DWORD unitCand[8];
        const int marines[4] = { 20, 21, 22, 23 };
        MakeCandidates(unitCand, marines, 4);
        DWORD uout[SC_SELECTION_SLOTS] = { 0 };
        uout[0] = FakeUnit(20);
        Check("a movable lead is untouched",
              (int)ScFanoutGrowBuildingGroup(unitCand, uout, 0, 1), 1);

        // ... and with it, the twelve-unit chunking is exactly what part [7] asserted:
        // this is the regression guard on `chunk = simSlots`.
        for (int i = 0; i < 64; ++i) SetFakeType(i, FAKE_TYPE_MARINE);
        MakeUnits(64, 1);
        for (int i = 0; i < 64; ++i) SetFakeType(i, FAKE_TYPE_MARINE);
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ScFanoutTestSetMovable(&FakeMovable);
        SetFakeUnitsDatFlags();
        DriveSelection(36);
        Check("36 ordinary units still chunk by twelve", ScFanoutSimSlots(), SC_SELECTION_SLOTS);
        g_captureLen = 0; g_captureCount = 0;
        (void)ScFanoutOnCommand(kRightClick, sizeof(kRightClick));
        Check("  3 pairs, not 36", g_captureCount, 6);
        Check("  bytes queued unchanged from part [7]", g_captureLen, 108);
    }

    ScFanoutTestSetMovable(NULL);
    VirtualFree(g_fake, 0, MEM_RELEASE);
    g_fake = NULL;
}

// ---------------------------------------------------------------------------
// [20] Building-group PARITY (task 036): extending a group, and recalling one.
//
// Two mechanisms, neither of which goes through SortAllUnits:
//
//   the EXTEND override -- ScFanoutMovableDecide, the decision half of the detour on
//   unit_IsStandardAndMovable. It is asked (unit, return address, the engine's verdict)
//   and answers what the caller should see. Everything about it is decidable offline:
//   the allowlist, the "is the lead a building" test, and the same-type-and-owner rule.
//
//   the RECALL re-install -- a control group of buildings must end up in the ENGINE's
//   client selection, not only in the shadow list, because the stock status row draws
//   the engine's array. The engine call is replaced by a recorder here, so the test can
//   assert WHAT would have been installed as well as that something was.
// ---------------------------------------------------------------------------

// The recorder standing in for CreateNewUnitSelectionsFromList. It does what the engine
// does that this plugin depends on: write the list into activePlayerSelection, densely
// from slot 0 and NULL-terminated -- which is what ReadEngineVisible reads back.
static DWORD g_reinstallList[SC_SELECTION_SLOTS];
static int   g_reinstallCount = -1;
static int   g_reinstallCalls = 0;

static void FakeCreateSelections(unsigned long* list, int count) {
    g_reinstallCount = count;
    ++g_reinstallCalls;
    DWORD* active = (DWORD*)FakeRt(SC_VA_ACTIVE_PLAYER_SELECTION);
    for (int i = 0; i < SC_SELECTION_SLOTS; ++i) active[i] = 0;
    for (int i = 0; i < count && i < SC_SELECTION_SLOTS; ++i) {
        g_reinstallList[i] = (DWORD)list[i];
        active[i] = (DWORD)list[i];
    }
}

static void SetFakeEngineSelection(const int* idx, int n) {
    DWORD* active = (DWORD*)FakeRt(SC_VA_ACTIVE_PLAYER_SELECTION);
    for (int i = 0; i < SC_SELECTION_SLOTS; ++i) active[i] = 0;
    for (int i = 0; i < n && i < SC_SELECTION_SLOTS; ++i) active[i] = FakeUnit(idx[i]);
}

static void BuildingParityTests(void) {
    Part("building-group parity: extend a group, recall a group");

    g_fake = (BYTE*)VirtualAlloc(NULL, FAKE_IMAGE_BYTES, MEM_COMMIT | MEM_RESERVE,
                                 PAGE_READWRITE);
    if (!g_fake) { printf("  FAIL could not allocate the fake image\n"); ++g_failures; return; }

    MakeUnits(64, 1);
    ResetQueueCounters();
    ScFanoutTestBegin(g_fake, &CaptureEmit, 4000);
    ScFanoutTestSetMovable(&FakeMovable);
    SetFakeUnitsDatFlags();

    // 0..5 Barracks, 6..9 Supply Depots, 10.. Marines.
    for (int i = 0; i < 6; ++i)   SetFakeType(i, FAKE_TYPE_BARRACKS);
    for (int i = 6; i < 10; ++i)  SetFakeType(i, FAKE_TYPE_DEPOT);
    for (int i = 10; i < 64; ++i) SetFakeType(i, FAKE_TYPE_MARINE);

    // The four allowlisted return addresses, in the fake image's own address space.
    const DWORD retShiftLead = (DWORD)FakeRt(SC_RET_MOVABLE_SHIFT_LEAD);
    const DWORD retShiftHit  = (DWORD)FakeRt(SC_RET_MOVABLE_SHIFT_CLICKED);
    const DWORD retCombNew   = (DWORD)FakeRt(SC_RET_MOVABLE_COMBINE_NEW);
    const DWORD retCombOld   = (DWORD)FakeRt(SC_RET_MOVABLE_COMBINE_OLD);

    printf("\n    the extend override answers ONLY at the four call sites\n");
    {
        const int leadIdx[1] = { 0 };
        SetFakeEngineSelection(leadIdx, 1);            // lead: a Barracks

        // POSITIVE FIRST, so the negatives below are worth something: the same unit, the
        // same lead, allowed at an allowlisted site.
        Check("a sibling Barracks is allowed at the shift-click site",
              ScFanoutMovableDecide(FakeUnit(1), retShiftHit, 0), 1);

        // ... and refused everywhere else in the binary, with the engine's own answer
        // handed straight back. 0x0046F1AA is SortAllUnits' own call site -- a real
        // address, deliberately, so this is "not in the allowlist" rather than "not a
        // code address at all".
        Check("SortAllUnits' own call site is NOT in the allowlist",
              ScFanoutMovableDecide(FakeUnit(1), (DWORD)FakeRt(0x0046F1AAu), 0), 0);
        Check("nor is an arbitrary return address",
              ScFanoutMovableDecide(FakeUnit(1), (DWORD)FakeRt(0x00401000u), 0), 0);
        Check("and a PASSING verdict is handed back unchanged off-allowlist",
              ScFanoutMovableDecide(FakeUnit(20), (DWORD)FakeRt(0x00401000u), 1), 1);
    }

    printf("\n    with a BUILDING lead, membership is same type and same owner\n");
    {
        const int leadIdx[1] = { 0 };
        SetFakeEngineSelection(leadIdx, 1);
        Check("the lead itself passes at its own site",
              ScFanoutMovableDecide(FakeUnit(0), retShiftLead, 0), 1);
        Check("a sibling Barracks joins",  ScFanoutMovableDecide(FakeUnit(2), retShiftHit, 0), 1);
        Check("a Supply Depot does not",   ScFanoutMovableDecide(FakeUnit(6), retShiftHit, 0), 0);
        // The engine SAID YES for a Marine. Refusing it here is not a regression: with a
        // building lead, vanilla refused the whole operation at the lead's own call site,
        // so this replaces "nothing happens" with "nothing happens".
        Check("a Marine does not, even though the engine allowed it",
              ScFanoutMovableDecide(FakeUnit(20), retShiftHit, 1), 0);

        *(BYTE*)(FakeUnit(3) + SC_CUNIT_OFF_PLAYER) = 2;
        BuildFakePlayerList(64, 1);
        Check("another player's Barracks does not",
              ScFanoutMovableDecide(FakeUnit(3), retShiftHit, 0), 0);
        *(BYTE*)(FakeUnit(3) + SC_CUNIT_OFF_PLAYER) = 1;
        BuildFakePlayerList(64, 1);

        const DWORD hpWas = *(DWORD*)(FakeUnit(4) + SC_CUNIT_OFF_HITPOINTS);
        *(DWORD*)(FakeUnit(4) + SC_CUNIT_OFF_HITPOINTS) = 0;
        Check("a destroyed Barracks does not", ScFanoutMovableDecide(FakeUnit(4), retShiftHit, 0), 0);
        *(DWORD*)(FakeUnit(4) + SC_CUNIT_OFF_HITPOINTS) = hpWas;

        // Both combine sites take the same rule -- that is what makes shift+box and
        // shift+ctrl-click agree with shift-click instead of each having its own answer.
        Check("the combine sites answer identically (existing lead)",
              ScFanoutMovableDecide(FakeUnit(0), retCombOld, 0), 1);
        Check("the combine sites answer identically (incoming list)",
              ScFanoutMovableDecide(FakeUnit(5), retCombNew, 0), 1);
        Check("... and refuse a different building type there too",
              ScFanoutMovableDecide(FakeUnit(6), retCombNew, 0), 0);
    }

    printf("\n    with a UNIT lead nothing is overridden at all\n");
    {
        const int marineLead[1] = { 20 };
        SetFakeEngineSelection(marineLead, 1);
        const int seen = ScFanoutExtendStat(SC_FANOUT_EXTEND_SEEN);
        Check("a Marine joining Marines is the engine's own answer",
              ScFanoutMovableDecide(FakeUnit(21), retShiftHit, 1), 1);
        Check("a Barracks shift-clicked onto Marines stays refused",
              ScFanoutMovableDecide(FakeUnit(0), retShiftHit, 0), 0);
        // The counter is the proof that this branch was never entered, rather than
        // entered and coincidentally agreeing.
        Check("  and the override never even ran", ScFanoutExtendStat(SC_FANOUT_EXTEND_SEEN) - seen, 0);
    }

    printf("\n    with the feature OFF the override is inert\n");
    {
        const int leadIdx[1] = { 0 };
        SetFakeEngineSelection(leadIdx, 1);
        ScFanoutTestSetBuildingGroups(false);
        const int seen = ScFanoutExtendStat(SC_FANOUT_EXTEND_SEEN);
        Check("a sibling Barracks is refused again", ScFanoutMovableDecide(FakeUnit(1), retShiftHit, 0), 0);
        Check("  because the override did not run", ScFanoutExtendStat(SC_FANOUT_EXTEND_SEEN) - seen, 0);
        ScFanoutTestSetBuildingGroups(true);
        Check("and allowed once more when it is back on",
              ScFanoutMovableDecide(FakeUnit(1), retShiftHit, 0), 1);
    }

    printf("\n    a control group of buildings recalls into the ENGINE's own selection\n");
    {
        MakeUnits(64, 1);
        ScFanoutTestBegin(g_fake, &CaptureEmit, 4000);
        ScFanoutTestSetMovable(&FakeMovable);
        SetFakeUnitsDatFlags();
        for (int i = 0; i < 6; ++i)   SetFakeType(i, FAKE_TYPE_BARRACKS);
        for (int i = 6; i < 64; ++i)  SetFakeType(i, FAKE_TYPE_MARINE);
        ScFanoutTestSetCreateSelections(&FakeCreateSelections);
        g_reinstallCount = -1; g_reinstallCalls = 0;

        // Six Barracks selected, exactly as the drag box leaves them.
        DWORD sel[6];
        for (int i = 0; i < 6; ++i) sel[i] = FakeUnit(i);
        ScFanoutOnSelect(6, sel);
        Check("the shadow list holds six buildings", ScFanoutShadowCount(), 6);
        Check("the sim holds ONE of them at a time", ScFanoutSimSlots(), 1);

        // Ctrl+1.
        const BYTE assign[3] = { 0x13, SC_HOTKEY_ASSIGN, 0x01 };
        (void)ScFanoutOnCommand(assign, sizeof(assign));
        Check("the plugin's group holds all six", ScFanoutGroupCount(1), 6);

        // Press 1. THE ENGINE HANDS BACK ONE, which is not a fault in its recall: its own
        // row was filled from playersSelections, and the sim gate capped that at one
        // building. This is the measured shape -- the in-game -Measure arm read exactly
        // `GROUP recall enter: ... visible=1` against six stored.
        const int engineGave[1] = { 0 };
        SetFakeEngineSelection(engineGave, 1);
        const BYTE recall[3] = { 0x13, SC_HOTKEY_RECALL, 0x01 };
        (void)ScFanoutOnCommand(recall, sizeof(recall));

        Check("the engine's client selection was rebuilt exactly once", g_reinstallCalls, 1);
        Check("  with all six buildings, not the one it handed back", g_reinstallCount, 6);
        bool allSix = true;
        for (int i = 0; i < 6; ++i) {
            bool found = false;
            for (int j = 0; j < g_reinstallCount && j < SC_SELECTION_SLOTS; ++j) {
                if (g_reinstallList[j] == FakeUnit(i)) found = true;
            }
            if (!found) allSix = false;
        }
        Check("  and each of them by its own pointer", allSix ? 1 : 0, 1);
        Check("the shadow list still holds six", ScFanoutShadowCount(), 6);
        Check("  and the engine is now holding all six of them, not one",
              ScFanoutVisibleCount(), 6);
        Check("  so nothing is past the cap any more",
              ScFanoutShadowCount() - ScFanoutVisibleCount(), 0);
        Check("the chunk size is still ONE -- the SIM gate is untouched", ScFanoutSimSlots(), 1);

        // The order still reaches every one of them, one Select per building. This is the
        // half that already worked before task 036 and must not have been disturbed by
        // re-ordering the shadow list.
        g_captureLen = 0; g_captureCount = 0;
        (void)ScFanoutOnCommand(kRightClick, sizeof(kRightClick));
        Check("6 pairs x (Select + order)", g_captureCount, 12);
        Check("every building is on the wire by its own tag", CaptureTagCount(10), 6);
        bool all6 = true;
        for (int i = 0; i < 6; ++i) if (!CaptureHasTag(ExpectTag(i), 10)) all6 = false;
        Check("  and each of the six is one of them", all6 ? 1 : 0, 1);
    }

    printf("\n    a control group of UNITS recalls exactly as task 021 left it\n");
    {
        // THE REGRESSION GUARD on the branch above. With 36 Marines the engine hands back
        // its own twelve and the re-install must not run at all -- if it did, the shadow
        // list's overflow-first invariant would be rebuilt from a different source and
        // part [11]'s numbers would move.
        MakeUnits(64, 1);
        ScFanoutTestBegin(g_fake, &CaptureEmit, 4000);
        ScFanoutTestSetMovable(&FakeMovable);
        SetFakeUnitsDatFlags();
        for (int i = 0; i < 64; ++i) SetFakeType(i, FAKE_TYPE_MARINE);
        ScFanoutTestSetCreateSelections(&FakeCreateSelections);
        g_reinstallCount = -1; g_reinstallCalls = 0;

        DriveSelection(36);
        Check("36 units captured", ScFanoutShadowCount(), 36);
        const BYTE assign[3] = { 0x13, SC_HOTKEY_ASSIGN, 0x02 };
        (void)ScFanoutOnCommand(assign, sizeof(assign));
        Check("the group holds 36", ScFanoutGroupCount(2), 36);

        int twelve[SC_SELECTION_SLOTS];
        for (int i = 0; i < SC_SELECTION_SLOTS; ++i) twelve[i] = 24 + i;   // the visible tail
        SetFakeEngineSelection(twelve, SC_SELECTION_SLOTS);
        const BYTE recall[3] = { 0x13, SC_HOTKEY_RECALL, 0x02 };
        (void)ScFanoutOnCommand(recall, sizeof(recall));

        Check("the engine's selection was NOT rebuilt for a unit group", g_reinstallCalls, 0);
        Check("all 36 came back", ScFanoutShadowCount(), 36);
        Check("  with the engine holding twelve", ScFanoutVisibleCount(), SC_SELECTION_SLOTS);
        Check("  and the chunk size back at twelve", ScFanoutSimSlots(), SC_SELECTION_SLOTS);
    }

    ScFanoutTestSetCreateSelections(NULL);
    ScFanoutTestSetMovable(NULL);
    VirtualFree(g_fake, 0, MEM_RELEASE);
    g_fake = NULL;
}

// ---------------------------------------------------------------------------
// [12] the process-exit log path (task 023)
//
// THE FAILURE THIS PINS DOWN. One run's detach wrote NOTHING -- no STATS, no
// GROUPSTATS, no CIRCLES stats, not even DETACH -- and test-selection-circles
// failed on the missing CIRCLES line while the plugin had done nothing wrong
// (task 021 found it, task 022 found the mechanism). ScLog's exit mode used a
// TryEnterCriticalSection and returned on the first failure; on the exit path the
// lock's owner is a thread the OS has already terminated, so it never comes back
// and every line of the sequence is dropped.
//
// The test holds the log lock from ANOTHER THREAD that never releases it -- which
// is the dead-owner state, reproduced exactly -- and requires the line to land
// anyway. It fails against the old code by construction: TryEnterCriticalSection
// cannot succeed while a different thread owns the section.
// ---------------------------------------------------------------------------

static HANDLE g_lockHeld = NULL;    // signalled once the holder owns the lock
static HANDLE g_lockDrop = NULL;    // signalled to make the holder let go

static DWORD WINAPI LockHolderThread(LPVOID) {
    if (!ScLogTestTryHoldLock()) { SetEvent(g_lockHeld); return 1; }
    SetEvent(g_lockHeld);
    WaitForSingleObject(g_lockDrop, 30000);
    ScLogTestReleaseLock();
    return 0;
}

// How many lines of `path` contain `needle`.
static int CountLines(const char* path, const char* needle) {
    FILE* f = fopen(path, "rb");
    if (!f) return -1;
    char buf[4096];
    int n = 0;
    while (fgets(buf, sizeof(buf), f)) { if (strstr(buf, needle)) ++n; }
    fclose(f);
    return n;
}

// ---------------------------------------------------------------------------
// [15] The production-queue core (task 025), driven with no game and no hooks.
// Renumbered from [11] by task 026: task 021's shadow control groups already held that
// number and four passages in research/control-groups.md cite `hooktest part [11]` for
// it. Two parts sharing a number defeats the only thing the numbers are for -- naming
// which part failed in a redirected log -- and the collision was invisible to both sides
// because each merged cleanly on its own.
//
// Everything the feature can do to a player's resources happens in three functions --
// ScProdQueueOnTrain, ScProdQueueOnTick, ScProdQueueOnCancel -- and all three take a
// CUnit* and read/write globals that live inside the fake image. So the whole
// "paid exactly once, refunded exactly once" claim is decidable HERE, arithmetically,
// against a counter this test owns, instead of only in a game run where a stray
// mineral is invisible.
// ---------------------------------------------------------------------------

#define PQ_BUILDING   0        // fake unit index used as the producing building
#define PQ_TYPE_A     0x00     // Terran Marine's id; any id under 0x6A works here
#define PQ_TYPE_B     0x07
#define PQ_TYPE_FREE  0x40     // given the units.dat "moves no resources" bit below
#define PQ_PLAYER     1

static DWORD PqBuilding(void) { return FakeUnit(PQ_BUILDING); }

static void PqSetCost(unsigned type, WORD minerals, WORD gas, bool movesResources) {
    *(WORD*)((DWORD)FakeRt(SC_VA_UNIT_MINERAL_COST) + type * 2) = minerals;
    *(WORD*)((DWORD)FakeRt(SC_VA_UNIT_GAS_COST)     + type * 2) = gas;
    BYTE* flag = (BYTE*)((DWORD)FakeRt(SC_VA_UNIT_COST_FLAGS) + type * 4);
    *flag = movesResources ? 0 : SC_UNIT_COST_FLAG_NO_SPEND;
}

static DWORD* PqMinerals(void) {
    return (DWORD*)((DWORD)FakeRt(SC_VA_PLAYER_MINERALS) + PQ_PLAYER * 4);
}
static DWORD* PqGas(void) {
    return (DWORD*)((DWORD)FakeRt(SC_VA_PLAYER_GAS) + PQ_PLAYER * 4);
}

// Fill the engine's five slots with `n` occupied entries, head at slot 0.
static void PqSetEngineQueue(int n, WORD type) {
    DWORD u = PqBuilding();
    *(BYTE*)(u + SC_CUNIT_OFF_BUILD_QUEUE_SLOT) = 0;
    for (int i = 0; i < SC_BUILD_QUEUE_SLOTS; ++i) {
        *(WORD*)(u + SC_CUNIT_OFF_BUILD_QUEUE + i * 2) =
            (i < n) ? type : (WORD)SC_BUILD_QUEUE_EMPTY;
    }
}
static WORD PqEngineSlot(int i) {
    return *(WORD*)(PqBuilding() + SC_CUNIT_OFF_BUILD_QUEUE + i * 2);
}
static int PqEngineLen(void) {
    int n = 0;
    for (int i = 0; i < SC_BUILD_QUEUE_SLOTS; ++i) {
        if (PqEngineSlot(i) != SC_BUILD_QUEUE_EMPTY) ++n;
    }
    return n;
}

// findFreeBuildQueueSlot (0x004669B0), modelled: from the head, wrapping, five tries.
static int PqFreeSlot(void) {
    DWORD u = PqBuilding();
    unsigned slot = *(BYTE*)(u + SC_CUNIT_OFF_BUILD_QUEUE_SLOT);
    for (int tries = SC_BUILD_QUEUE_SLOTS; tries > 0; --tries) {
        if (slot >= SC_BUILD_QUEUE_SLOTS) slot = 0;
        if (PqEngineSlot((int)slot) == SC_BUILD_QUEUE_EMPTY) return (int)slot;
        ++slot;
    }
    return SC_BUILD_QUEUE_SLOTS;
}

// ONE PRESS OF TRAIN, with the ENGINE's half modelled first -- because under this design
// the engine is the only thing that ever pays, and a test that let the plugin pay would
// be testing a different program. addToBuildQueue (0x00467250) takes the first free slot,
// stores the type there and deducts the cost; it does nothing at all if the ring is full,
// if the id is out of range, or if the player cannot afford it. Then the post-hook runs,
// which is what the detour does.
static void PqTrain(unsigned type) {
    DWORD u = PqBuilding();
    int   slot = PqFreeSlot();
    bool  wasFull = slot >= SC_BUILD_QUEUE_SLOTS;
    if (!wasFull && type < SC_MAX_TRAINABLE_UNIT_ID) {
        BYTE* flag = (BYTE*)((DWORD)FakeRt(SC_VA_UNIT_COST_FLAGS) + type * 4);
        WORD  min  = *(WORD*)((DWORD)FakeRt(SC_VA_UNIT_MINERAL_COST) + type * 2);
        WORD  gas  = *(WORD*)((DWORD)FakeRt(SC_VA_UNIT_GAS_COST) + type * 2);
        bool  free_ = (*flag & SC_UNIT_COST_FLAG_NO_SPEND) != 0;
        if (free_ || (*PqMinerals() >= min && *PqGas() >= gas)) {
            *(WORD*)(u + SC_CUNIT_OFF_BUILD_QUEUE + slot * 2) = (WORD)type;
            if (!free_) { *PqMinerals() -= min; *PqGas() -= gas; }
        }
    }
    ScProdQueueOnTrain(u, type, wasFull);
}

// Folds the "not tracked" sentinel (-1) to 0, for the places that want a LENGTH.
static int PqOverflow(void) {
    int n = ScProdQueueOverflowCount(PqBuilding());
    return n < 0 ? 0 : n;
}

static void PqBegin(int maxTotal, DWORD minerals, DWORD gas) {
    MakeUnits(8, PQ_PLAYER);
    PqSetCost(PQ_TYPE_A, 50, 0, true);
    PqSetCost(PQ_TYPE_B, 100, 25, true);
    PqSetCost(PQ_TYPE_FREE, 999, 999, false);   // cost table filled, flag says ignore it
    *PqMinerals() = minerals;
    *PqGas()      = gas;
    PqSetEngineQueue(0, PQ_TYPE_A);   // an EMPTY building; PqTrain fills it the engine's way
    ScProdQueueTestBegin(g_fake, maxTotal);
}

static void ProdQueueTests(void) {
    Part("the production-queue core: >5 queued, no game, no hooks");

    if (!g_fake) {
        g_fake = (BYTE*)VirtualAlloc(NULL, FAKE_IMAGE_BYTES, MEM_COMMIT | MEM_RESERVE,
                                     PAGE_READWRITE);
        if (!g_fake) { printf("  FAIL could not allocate the fake image\n"); ++g_failures; return; }
    }

    printf("\n    the FIFTH item is taken back out of the ring -- and the plugin pays nothing\n");
    PqBegin(16, 1000, 500);
    for (int i = 0; i < 5; ++i) PqTrain(PQ_TYPE_A);
    Check("the ring is held one below the engine's five", PqEngineLen(), SC_PRODQ_ENGINE_HOLD);
    Check("and the fifth item is with the plugin", ScProdQueueOverflowCount(PqBuilding()), 1);
    Check("so the logical queue is five",  PqEngineLen() + PqOverflow(), 5);
    // "and the plugin spent NOTHING" used to be asserted here from the plugin's own
    // MINERALS_SPENT counter. Deleted with the counter (issue #66): the line above is the
    // same claim read out of the engine's resource global, and it is the one that fails
    // when a spend is actually added -- measured, work/scratch/055-defect.
    Check("the ENGINE paid for all five",  (long long)*PqMinerals(), 1000 - 5 * 50);
    Check("held counter",                  ScProdQueueStat(SC_PRODQ_STAT_CAPTURED), 1);

    printf("\n    a queue under the hold is left ENTIRELY to the engine\n");
    PqBegin(16, 1000, 500);
    for (int i = 0; i < 3; ++i) PqTrain(PQ_TYPE_A);
    Check("nothing held", ScProdQueueOverflowCount(PqBuilding()), -1);
    Check("no building tracked", ScProdQueueTrackedBuildings(), 0);
    Check("all three are in the ring", PqEngineLen(), 3);
    Check("the plugin moved no money", (long long)*PqMinerals(), 1000 - 3 * 50);

    printf("\n    FIFO: a freed slot takes the OLDEST held item, and pays nothing\n");
    PqBegin(16, 1000, 500);
    for (int i = 0; i < 5; ++i) PqTrain(PQ_TYPE_A);   // fifth is held
    PqTrain(PQ_TYPE_B);                               // sixth is held behind it
    Check("two items held", ScProdQueueOverflowCount(PqBuilding()), 2);
    Check("head of the held list is the FIFTH one queued",
          ScProdQueueOverflowAt(PqBuilding(), 0), PQ_TYPE_A);
    Check("and the sixth is behind it",
          ScProdQueueOverflowAt(PqBuilding(), 1), PQ_TYPE_B);
    {
        DWORD mineralsAfterHold = *PqMinerals();
        // The engine finishes the head item and frees its slot, as productionTick does.
        // The ring now runs 1,2,3 with the head at 1, so the slot the engine's own
        // free-slot rule offers next is 4 -- NOT the one just vacated, which is behind
        // the head and unreachable until the ring wraps round to it.
        *(WORD*)(PqBuilding() + SC_CUNIT_OFF_BUILD_QUEUE) = SC_BUILD_QUEUE_EMPTY;
        *(BYTE*)(PqBuilding() + SC_CUNIT_OFF_BUILD_QUEUE_SLOT) = 1;
        ScProdQueueOnTick(PqBuilding());
        Check("the next free slot now holds the OLDEST held item", PqEngineSlot(4), PQ_TYPE_A);
        Check("one item left with the plugin", ScProdQueueOverflowCount(PqBuilding()), 1);
        Check("and it is the SIXTH one queued",
              ScProdQueueOverflowAt(PqBuilding(), 0), PQ_TYPE_B);
        Check("promotion moved NO money", (long long)*PqMinerals(),
              (long long)mineralsAfterHold);
        Check("promoted counter", ScProdQueueStat(SC_PRODQ_STAT_PROMOTED), 1);
    }

    printf("\n    two freed slots promote two items, in order, in one tick\n");
    PqBegin(16, 1000, 500);
    for (int i = 0; i < 5; ++i) PqTrain(PQ_TYPE_A);
    PqTrain(PQ_TYPE_B);
    // Two items complete: the ring is left holding 2 and 3 with the head at 2, so the
    // free slots the engine's rule offers, in order, are 4 and then 0.
    *(WORD*)(PqBuilding() + SC_CUNIT_OFF_BUILD_QUEUE + 0 * 2) = SC_BUILD_QUEUE_EMPTY;
    *(WORD*)(PqBuilding() + SC_CUNIT_OFF_BUILD_QUEUE + 1 * 2) = SC_BUILD_QUEUE_EMPTY;
    *(BYTE*)(PqBuilding() + SC_CUNIT_OFF_BUILD_QUEUE_SLOT) = 2;
    ScProdQueueOnTick(PqBuilding());
    Check("the first free slot took the first item",  PqEngineSlot(4), PQ_TYPE_A);
    Check("the second free slot took the second",     PqEngineSlot(0), PQ_TYPE_B);
    Check("everything drained, record dropped",       ScProdQueueTrackedBuildings(), 0);

    printf("\n    the ring WRAPS: with the head at 3, promotion goes 3 then 4, never 0\n");
    PqBegin(16, 1000, 500);
    for (int i = 0; i < 5; ++i) PqTrain(PQ_TYPE_A);
    PqTrain(PQ_TYPE_B);                                        // held behind the fifth A
    PqSetEngineQueue(0, PQ_TYPE_A);                            // empty the ring outright
    *(BYTE*)(PqBuilding() + SC_CUNIT_OFF_BUILD_QUEUE_SLOT) = 3;
    ScProdQueueOnTick(PqBuilding());
    Check("slot 3 (the head) took the first held item", PqEngineSlot(3), PQ_TYPE_A);
    Check("slot 4 took the second",                     PqEngineSlot(4), PQ_TYPE_B);
    Check("slot 0 was never written",  PqEngineSlot(0), SC_BUILD_QUEUE_EMPTY);
    Check("and both were handed over", ScProdQueueTrackedBuildings(), 0);

    printf("\n    cancel-last (payload 0xFE) is CONSUMED and refunds exactly once\n");
    PqBegin(16, 1000, 500);
    for (int i = 0; i < 5; ++i) PqTrain(PQ_TYPE_A);
    PqTrain(PQ_TYPE_B);
    Check("the engine paid for all six", (long long)*PqMinerals(), 1000 - 5 * 50 - 100);
    Check("gas paid for the sixth",      (long long)*PqGas(), 500 - 25);
    Check("the plugin consumes it",
          ScProdQueueOnCancel(PqBuilding(), SC_CANCEL_TRAIN_LAST) ? 1 : 0, 1);
    Check("the LAST item came back (type B)", (long long)*PqMinerals(), 1000 - 5 * 50);
    Check("its gas came back too",            (long long)*PqGas(), 500);
    Check("one item left",                    ScProdQueueOverflowCount(PqBuilding()), 1);
    Check("cancelling again returns the fifth",
          ScProdQueueOnCancel(PqBuilding(), SC_CANCEL_TRAIN_LAST) ? 1 : 0, 1);
    Check("balance is the four still in the ring, and nothing else",
          (long long)*PqMinerals(), 1000 - 4 * 50);
    Check("record dropped",                   ScProdQueueTrackedBuildings(), 0);
    Check("a further cancel is the ENGINE's",
          ScProdQueueOnCancel(PqBuilding(), SC_CANCEL_TRAIN_LAST) ? 1 : 0, 0);

    printf("\n    a cancel naming a slot the RING HOLDS is the engine's; one it does not is ours\n");
    // Task 033 changed this contract, and the change is the whole point of the fifth icon.
    // The ring holds four (SC_PRODQ_ENGINE_HOLD) and the plugin holds one, so display
    // indices 0..3 name real ring items -- the engine's, passed through, exactly as before
    // -- while display 4 names a slot holding 0xE4. Before task 033 that click could not
    // exist (an empty slot's icon is drawn DISABLED); now the indicator draws that icon
    // from the plugin's overflow and lights it, so the click is real and the plugin owns
    // the item behind it. Handing it to the engine would refund by type 0xE4.
    PqBegin(16, 1000, 500);
    for (int i = 0; i < 5; ++i) PqTrain(PQ_TYPE_A);
    Check("the ring holds four, the plugin one", PqEngineLen(), SC_PRODQ_ENGINE_HOLD);
    for (unsigned slot = 0; slot < (unsigned)SC_PRODQ_ENGINE_HOLD; ++slot) {
        Check("a slot the ring HOLDS passes through",
              ScProdQueueOnCancel(PqBuilding(), slot) ? 1 : 0, 0);
    }
    Check("0xFF (the no-op form) passes through",
          ScProdQueueOnCancel(PqBuilding(), SC_CANCEL_TRAIN_NONE) ? 1 : 0, 0);
    Check("none of that touched what the plugin holds",
          ScProdQueueOverflowCount(PqBuilding()), 1);
    Check("nor the money", (long long)*PqMinerals(), 1000 - 5 * 50);
    Check("the display index past the ring is CONSUMED",
          ScProdQueueOnCancel(PqBuilding(), (unsigned)SC_PRODQ_ENGINE_HOLD) ? 1 : 0, 1);
    Check("  and it refunded exactly that one item",
          (long long)*PqMinerals(), 1000 - 4 * 50);
    Check("  the plugin holds nothing now", ScProdQueueTrackedBuildings(), 0);
    Check("a repeat of the same click is SWALLOWED, not passed to the engine",
          ScProdQueueOnCancel(PqBuilding(), (unsigned)SC_PRODQ_ENGINE_HOLD) ? 1 : 0, 1);
    Check("  and refunds nothing a second time", (long long)*PqMinerals(), 1000 - 4 * 50);

    printf("\n    THE CAP: the plugin stops taking items back, and vanilla's own five refuses\n");
    PqBegin(8, 1000, 500);              // 8 = the engine's five plus three held
    for (int i = 0; i < 8; ++i) PqTrain(PQ_TYPE_A);
    Check("three held",             ScProdQueueOverflowCount(PqBuilding()), 3);
    Check("and the ring is left FULL, which is what refuses the ninth",
          PqEngineLen(), SC_BUILD_QUEUE_SLOTS);
    Check("logical length is exactly the maximum", PqEngineLen() + PqOverflow(), 8);
    Check("the engine paid for eight",  (long long)*PqMinerals(), 1000 - 8 * 50);
    // A ninth command that still reaches the handler -- vanilla's UI would not send it,
    // but a replay or a network peer can -- is dropped by the engine at its own CMP EAX,5
    // and counted, and costs the player nothing.
    PqTrain(PQ_TYPE_A);
    Check("a ninth is refused",     ScProdQueueStat(SC_PRODQ_STAT_REFUSED_FULL), 1);
    Check("still eight",            PqEngineLen() + PqOverflow(), 8);
    Check("and it cost nothing",    (long long)*PqMinerals(), 1000 - 8 * 50);

    printf("\n    an unaffordable item never reaches the plugin at all\n");
    PqBegin(16, 120, 0);
    PqTrain(PQ_TYPE_A);                 // 120 -> 70
    PqTrain(PQ_TYPE_A);                 // 70 -> 20
    PqTrain(PQ_TYPE_A);                 // the ENGINE cannot afford it: nothing happens
    Check("two are in the ring",         PqEngineLen(), 2);
    Check("nothing was held",            ScProdQueueTrackedBuildings(), 0);
    Check("balance never goes negative", (long long)*PqMinerals(), 20);

    printf("\n    a type units.dat says moves no resources moves none, either way\n");
    PqBegin(16, 1000, 500);
    for (int i = 0; i < 4; ++i) PqTrain(PQ_TYPE_FREE);
    PqTrain(PQ_TYPE_FREE);              // the fifth is the one the plugin holds
    Check("held", ScProdQueueOverflowCount(PqBuilding()), 1);
    Check("minerals untouched", (long long)*PqMinerals(), 1000);
    Check("gas untouched",      (long long)*PqGas(), 500);
    (void)ScProdQueueOnCancel(PqBuilding(), SC_CANCEL_TRAIN_LAST);
    Check("and the refund moves none either", (long long)*PqMinerals(), 1000);

    printf("\n    a type the Train handler itself would reject (>= 0x6A) is refused\n");
    PqBegin(16, 1000, 500);
    PqTrain(SC_MAX_TRAINABLE_UNIT_ID);
    Check("not tracked", ScProdQueueTrackedBuildings(), 0);
    Check("nothing in the ring", PqEngineLen(), 0);
    Check("money untouched", (long long)*PqMinerals(), 1000);

    printf("\n    the building dies: every held item is refunded, exactly once\n");
    PqBegin(16, 1000, 500);
    for (int i = 0; i < 5; ++i) PqTrain(PQ_TYPE_A);
    PqTrain(PQ_TYPE_B);
    Check("the engine paid for six", (long long)*PqMinerals(), 1000 - 5 * 50 - 100);
    // A damage death: the slot is not recycled, the hit points are zero. This is the
    // same signal sc_fanout's task-020 gate uses.
    *(DWORD*)(PqBuilding() + SC_CUNIT_OFF_HITPOINTS) = 0;
    ScProdQueueOnTick(FakeUnit(1));     // any other building's tick runs the sweep
    Check("record dropped",  ScProdQueueTrackedBuildings(), 0);
    // The two HELD items come back. The four still sitting in the ring are the engine's
    // to refund, through its own unit-removal path, and are not this feature's business.
    Check("both held items refunded", (long long)*PqMinerals(), 1000 - 4 * 50);
    Check("gas refunded too",         (long long)*PqGas(), 500);
    Check("refunded counter",         ScProdQueueStat(SC_PRODQ_STAT_REFUNDED), 2);

    printf("\n    a RECYCLED slot (uniqueness bumped) is a different building\n");
    PqBegin(16, 1000, 500);
    for (int i = 0; i < 5; ++i) PqTrain(PQ_TYPE_A);
    *(BYTE*)(PqBuilding() + SC_CUNIT_OFF_UNIQUENESS) += 1;
    ScProdQueueOnTick(FakeUnit(1));
    Check("record dropped", ScProdQueueTrackedBuildings(), 0);
    Check("the held item was refunded", (long long)*PqMinerals(), 1000 - 4 * 50);

    printf("\n    a building UNLINKED from the player list is gone (deep sweep only)\n");
    PqBegin(16, 1000, 500);
    for (int i = 0; i < 5; ++i) PqTrain(PQ_TYPE_A);
    UnlinkFakeUnit(PQ_BUILDING, PQ_PLAYER);
    ScProdQueueOnTick(FakeUnit(1));                 // fast sweep: cannot see this
    Check("the fast sweep leaves it alone", ScProdQueueTrackedBuildings(), 1);
    // The other building's own ring has to look EMPTY, or the deep-sweep call below would
    // read the fake image's zero-filled slots as five queued items and start managing it.
    // A real building's empty slots hold 0xE4, not 0.
    for (int s = 0; s < SC_BUILD_QUEUE_SLOTS; ++s) {
        *(WORD*)(FakeUnit(1) + SC_CUNIT_OFF_BUILD_QUEUE + s * 2) = (WORD)SC_BUILD_QUEUE_EMPTY;
    }
    ScProdQueueOnTrain(FakeUnit(1), PQ_TYPE_A, false);   // a player action: deep sweep
    Check("the deep sweep drops it", ScProdQueueTrackedBuildings(), 0);
    Check("refunded",                (long long)*PqMinerals(), 1000 - 4 * 50);
    RelinkFakeUnit(PQ_BUILDING, PQ_PLAYER);

    printf("\n    end to end: sixteen queued at one building, drained one slot at a time\n");
    PqBegin(16, 2000, 0);
    {
        const DWORD start = *PqMinerals();
        for (int i = 0; i < 16; ++i) PqTrain(PQ_TYPE_A);
        Check("eleven held",   ScProdQueueOverflowCount(PqBuilding()), 11);
        Check("and the ring is full, which is what stops a seventeenth",
              PqEngineLen(), SC_BUILD_QUEUE_SLOTS);
        Check("logical length is 16", PqEngineLen() + PqOverflow(), 16);
        Check("a seventeenth is refused",
              (PqTrain(PQ_TYPE_A), PqEngineLen() + PqOverflow()), 16);
        Check("the ENGINE paid for sixteen, once each",
              (long long)(start - *PqMinerals()), 16 * 50);

        // ScProdQueueOverflowCount reports -1 for a building it is not tracking, which
        // is NOT the same as 0 -- the loop has to fold that to zero or it exits one
        // item early, with the last one still sitting in the engine's ring.
        int built = 0;
        for (int frame = 0; frame < 64 && (PqEngineLen() + PqOverflow()) > 0; ++frame) {
            // The engine completes the head item and frees its slot.
            DWORD u = PqBuilding();
            BYTE head = *(BYTE*)(u + SC_CUNIT_OFF_BUILD_QUEUE_SLOT);
            if (*(WORD*)(u + SC_CUNIT_OFF_BUILD_QUEUE + head * 2) != SC_BUILD_QUEUE_EMPTY) {
                *(WORD*)(u + SC_CUNIT_OFF_BUILD_QUEUE + head * 2) = SC_BUILD_QUEUE_EMPTY;
                *(BYTE*)(u + SC_CUNIT_OFF_BUILD_QUEUE_SLOT) = (BYTE)((head + 1) % SC_BUILD_QUEUE_SLOTS);
                ++built;
            }
            ScProdQueueOnTick(u);
        }
        Check("all sixteen were built", built, 16);
        Check("nothing left in the engine's five", PqEngineLen(), 0);
        Check("nothing left in the plugin",        ScProdQueueTrackedBuildings(), 0);
        Check("promoted exactly the eleven", ScProdQueueStat(SC_PRODQ_STAT_PROMOTED), 11);
        Check("no refund happened",  ScProdQueueStat(SC_PRODQ_STAT_REFUNDED), 0);
        // THE PAY-ONCE IDENTITY. Every one of the sixteen was paid for by the engine at
        // the moment it accepted it; holding an item back and handing it over again are
        // bare stores. So the balance is down by sixteen costs -- not seventeen (the
        // refused one), and not twenty-seven (a second payment on each promotion).
        Check("total spend is sixteen costs, not seventeen and not twenty-seven",
              (long long)(start - *PqMinerals()), 16 * 50);
    }

    // -----------------------------------------------------------------------------
    // TASK 038. WHICH SELECTION ARRAY THE DETOURS READ, decided here because the two
    // arrays ABUT (0x006284B8 + 12*4 == 0x006284E8) and agree in every single-building
    // case -- so the wrong one passes every test that selects one building, which is
    // every test this part had until now.
    //
    // The engine's own gate walks playersSelections[activePlayerId]
    // (getActivePlayerNextSelection 0x0049A850, quoted in sc_prodqueue.cpp). The client's
    // activePlayerSelection is a different list, and a fanned-out Select+Train pair makes
    // them disagree on purpose: the SIMULATION is moved to one building at a time while
    // the player still has the whole group selected. Reading the client's list there
    // returned "no single building", the plugin held nothing, and every ring filled to
    // five -- the bug this task exists to fix.
    //
    // So each case below writes the two arrays to DIFFERENT things and says which one the
    // answer has to come from.
    // -----------------------------------------------------------------------------
    printf("\n    the building a receive handler acts on comes from the ENGINE's selection array\n");
    PqBegin(16, 1000, 500);
    {
        DWORD* engineSel = (DWORD*)FakeRt(SC_VA_PLAYERS_SELECTIONS) + PQ_PLAYER * SC_SELECTION_SLOTS;
        DWORD* clientSel = (DWORD*)FakeRt(SC_VA_ACTIVE_PLAYER_SELECTION);
        DWORD* activeId  = (DWORD*)FakeRt(SC_VA_ACTIVE_PLAYER_ID);
        for (int i = 0; i < SC_SELECTION_SLOTS; ++i) { engineSel[i] = 0; clientSel[i] = 0; }
        *activeId = PQ_PLAYER;

        // THE CASE THAT WAS BROKEN: the fan-out has just replayed Select(building 0), so
        // the simulation holds ONE building, while the player's own selection still holds
        // three. The answer is the simulation's building.
        engineSel[0] = FakeUnit(0);
        clientSel[0] = FakeUnit(0);
        clientSel[1] = FakeUnit(1);
        clientSel[2] = FakeUnit(2);
        Check("a group selected, the sim holding one -> that one",
              (long long)ScProdQueueSoleSelectedUnitForTest(), (long long)FakeUnit(0));

        // The next pair of the same fan-out names a different building. Reading the
        // client's list would have answered the same thing every time.
        engineSel[0] = FakeUnit(2);
        Check("the next pair of the same fan-out -> the NEXT building",
              (long long)ScProdQueueSoleSelectedUnitForTest(), (long long)FakeUnit(2));

        // THE NEGATIVE HALF, and it is the same test the engine makes: two units in the
        // SIMULATION's list means cmdrecvTrain does nothing at all, so neither may we.
        engineSel[1] = FakeUnit(3);
        Check("two in the sim's list -> not ours, the engine's own gate refuses too",
              (long long)ScProdQueueSoleSelectedUnitForTest(), 0LL);
        engineSel[1] = 0;

        // A player row is 12 slots and the row is indexed by activePlayerId: pointing the
        // id at a player with nothing selected must answer nothing, not another player's
        // building. This is what catches a wrong stride as well as a wrong base.
        *activeId = PQ_PLAYER + 1;
        Check("another player's row is empty -> nothing",
              (long long)ScProdQueueSoleSelectedUnitForTest(), 0LL);
        engineSel[SC_SELECTION_SLOTS] = FakeUnit(4);       // that neighbour's slot 0
        Check("and that row's own building is what it answers",
              (long long)ScProdQueueSoleSelectedUnitForTest(), (long long)FakeUnit(4));
        engineSel[SC_SELECTION_SLOTS] = 0;
        *activeId = PQ_PLAYER;

        // An id outside the eight players is fail-closed rather than an out-of-bounds read.
        *activeId = SC_MAX_PLAYERS;
        Check("an out-of-range active player -> nothing, and no read past the array",
              (long long)ScProdQueueSoleSelectedUnitForTest(), 0LL);
        *activeId = PQ_PLAYER;

        // And the whole point, stated as an assertion: what the CLIENT holds cannot
        // produce an answer on its own.
        engineSel[0] = 0;
        clientSel[0] = FakeUnit(1);
        Check("the client's list alone answers nothing -- it is not what the engine reads",
              (long long)ScProdQueueSoleSelectedUnitForTest(), 0LL);
    }

    ScProdQueueTestBegin(NULL, 0);   // leave the core inert for the parts after this
}

// ---------------------------------------------------------------------------
// [17] the upgrade-queue core (task 029), with no game and no hooks.
//
// Numbered 17, not 16: task 028's status-strip tests took 16 on main while this task was
// in flight, and the two collided on the merge. Two parts sharing a number defeats the
// only thing the numbers are for -- naming which part failed in a redirected log -- and
// this repo has now had that collision three times, each time invisible to both sides
// because each merged cleanly on its own.
//
// WHAT THIS HAS TO DECIDE, and why offline is the right place for it. The claim the
// whole feature rests on is "the plugin never moves a resource, and every item is paid
// for exactly once, by the engine, at the moment it starts". In a game run a stray
// mineral is invisible; here the fake image's resource globals are a counter this test
// owns, and the promotion seam (ScUpgStartFn) is a function this test writes -- so the
// engine's half can be modelled EXACTLY, including its refusals, and the arithmetic is
// decidable.
//
// The fake starter below is startUpgrade/startTech as research/upgrade-queue.md 5 reads
// them: check affordability, and only then set the field and subtract the cost. A test
// whose starter paid nothing would let a plugin that also paid look correct.
// ---------------------------------------------------------------------------

#define UQ_BUILDING 0
#define UQ_PLAYER   1
#define UQ_UPG_A    7      // Terran Infantry Weapons
#define UQ_UPG_B    0      // Terran Infantry Armor
#define UQ_TECH_A   0      // Stim Packs

static int g_uqStarted = 0;      // how many times the fake engine actually started one
static int g_uqGateRefuse = -1;  // an id the fake gate refuses outright, or -1

static DWORD UqBuilding(void) { return FakeUnit(UQ_BUILDING); }

static DWORD* UqMinerals(void) {
    return (DWORD*)((DWORD)FakeRt(SC_VA_PLAYER_MINERALS) + UQ_PLAYER * 4);
}
static DWORD* UqGas(void) {
    return (DWORD*)((DWORD)FakeRt(SC_VA_PLAYER_GAS) + UQ_PLAYER * 4);
}
static BYTE* UqUpgField(void)  { return (BYTE*)(UqBuilding() + SC_CUNIT_OFF_UPGRADE_PROGRESS); }
static BYTE* UqTechField(void) { return (BYTE*)(UqBuilding() + SC_CUNIT_OFF_TECH_PROGRESS); }

static void UqSetU16(DWORD table, unsigned index, WORD v) {
    *(WORD*)((DWORD)FakeRt(table) + index * 2) = v;
}

// The engine's own accept path, modelled: affordability first, then the field and the
// deduction. Returns 1 started, 0 cannot pay, -1 the gate refused.
static int UqFakeStart(DWORD unit, int kind, unsigned id) {
    if ((int)id == g_uqGateRefuse) return -1;
    DWORD m, g;
    if (kind == SC_UPGQ_KIND_TECH) {
        m = *(WORD*)((DWORD)FakeRt(SC_VA_TECH_MINERAL_COST) + id * 2);
        g = *(WORD*)((DWORD)FakeRt(SC_VA_TECH_GAS_COST) + id * 2);
    } else {
        DWORD lvl = *(BYTE*)((DWORD)FakeRt(SC_VA_UPGRADE_LEVEL) +
                             UQ_PLAYER * SC_UPGRADE_STRIDE_VANILLA + id);
        m = (WORD)(*(WORD*)((DWORD)FakeRt(SC_VA_UPGRADE_MINERAL_BASE) + id * 2) +
                   *(WORD*)((DWORD)FakeRt(SC_VA_UPGRADE_MINERAL_FACTOR) + id * 2) * lvl);
        g = (WORD)(*(WORD*)((DWORD)FakeRt(SC_VA_UPGRADE_GAS_BASE) + id * 2) +
                   *(WORD*)((DWORD)FakeRt(SC_VA_UPGRADE_GAS_FACTOR) + id * 2) * lvl);
    }
    if (*UqMinerals() < m || *UqGas() < g) return 0;
    if (kind == SC_UPGQ_KIND_TECH) *(BYTE*)(unit + SC_CUNIT_OFF_TECH_PROGRESS) = (BYTE)id;
    else                           *(BYTE*)(unit + SC_CUNIT_OFF_UPGRADE_PROGRESS) = (BYTE)id;
    *UqMinerals() -= m;
    *UqGas()      -= g;
    ++g_uqStarted;
    return 1;
}

// The engine finishing whatever is running: clear the field, as upgradeTick/techTick do.
static void UqFinishRunning(void) {
    *UqUpgField()  = (BYTE)SC_UPGRADE_NONE;
    *UqTechField() = (BYTE)SC_TECH_NONE;
}

static int UqQueued(void) {
    int n = ScUpgQueueCount(UqBuilding());
    return n < 0 ? 0 : n;
}

static void UqBegin(int maxTotal, DWORD minerals, DWORD gas) {
    MakeUnits(8, UQ_PLAYER);
    // A completed BUILDING. Both terms matter: CUnit+0xC8/0xC9 are a union arm and the
    // module refuses to read them for anything that is not a finished building.
    for (int i = 0; i < 8; ++i) {
        *(DWORD*)(FakeUnit(i) + SC_CUNIT_OFF_FLAGS) =
            SC_UNIT_FLAG_BUILDING | SC_UNIT_FLAG_COMPLETED;
        *(BYTE*)(FakeUnit(i) + SC_CUNIT_OFF_UPGRADE_PROGRESS) = (BYTE)SC_UPGRADE_NONE;
        *(BYTE*)(FakeUnit(i) + SC_CUNIT_OFF_TECH_PROGRESS)    = (BYTE)SC_TECH_NONE;
        *(BYTE*)(FakeUnit(i) + SC_CUNIT_OFF_UPGRADE_LEVEL)    = 0;
        *(WORD*)(FakeUnit(i) + SC_CUNIT_OFF_RESEARCH_TIME)    = 0;
    }
    // Costs, in the shape the engine reads them: upgrades are base + factor*level.
    UqSetU16(SC_VA_UPGRADE_MINERAL_BASE, UQ_UPG_A, 100);
    UqSetU16(SC_VA_UPGRADE_GAS_BASE,     UQ_UPG_A, 100);
    UqSetU16(SC_VA_UPGRADE_MINERAL_FACTOR, UQ_UPG_A, 75);
    UqSetU16(SC_VA_UPGRADE_GAS_FACTOR,     UQ_UPG_A, 75);
    UqSetU16(SC_VA_UPGRADE_MINERAL_BASE, UQ_UPG_B, 100);
    UqSetU16(SC_VA_UPGRADE_GAS_BASE,     UQ_UPG_B, 100);
    UqSetU16(SC_VA_UPGRADE_MINERAL_FACTOR, UQ_UPG_B, 75);
    UqSetU16(SC_VA_UPGRADE_GAS_FACTOR,     UQ_UPG_B, 75);
    UqSetU16(SC_VA_TECH_MINERAL_COST, UQ_TECH_A, 100);
    UqSetU16(SC_VA_TECH_GAS_COST,     UQ_TECH_A, 100);
    *(BYTE*)((DWORD)FakeRt(SC_VA_UPGRADE_LEVEL) +
             UQ_PLAYER * SC_UPGRADE_STRIDE_VANILLA + UQ_UPG_A) = 0;
    *UqMinerals() = minerals;
    *UqGas()      = gas;
    g_uqStarted = 0;
    g_uqGateRefuse = -1;
    ScUpgQueueTestBegin(g_fake, maxTotal, &UqFakeStart);
}

// One press: the engine's handler, modelled. The plugin gets first refusal; if it does
// not consume the command, the engine's own body runs and starts the item.
static void UqPress(int kind, unsigned id) {
    if (ScUpgQueueOnCommand(UqBuilding(), kind, id)) return;
    UqFakeStart(UqBuilding(), kind, id);
}

static void UpgradeQueueTests(void) {
    Part("the upgrade-queue core: more than one research at a building");

    if (!g_fake) {
        g_fake = (BYTE*)VirtualAlloc(NULL, FAKE_IMAGE_BYTES, MEM_COMMIT | MEM_RESERVE,
                                     PAGE_READWRITE);
        if (!g_fake) { printf("  FAIL could not allocate the fake image\n"); ++g_failures; return; }
    }

    printf("\n    an IDLE building is left entirely to the engine\n");
    UqBegin(8, 1000, 1000);
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_A);
    Check("the engine started it", g_uqStarted, 1);
    Check("and it is in the building's own field", (long long)*UqUpgField(), UQ_UPG_A);
    Check("the plugin holds nothing", ScUpgQueueCount(UqBuilding()), -1);
    Check("and tracks no building", ScUpgQueueTrackedBuildings(), 0);
    Check("the engine paid once", (long long)*UqMinerals(), 1000 - 100);

    printf("\n    the SECOND press is held by the plugin, and costs nothing\n");
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_B);
    Check("still only one engine start", g_uqStarted, 1);
    Check("the running upgrade is UNTOUCHED", (long long)*UqUpgField(), UQ_UPG_A);
    Check("the plugin holds the second", UqQueued(), 1);
    Check("its id", ScUpgQueueIdAt(UqBuilding(), 0), UQ_UPG_B);
    // THE HEADLINE OF THIS PART. A held item is unpaid, so the balance has not moved.
    Check("NOTHING was paid for the held item", (long long)*UqMinerals(), 1000 - 100);

    printf("\n    it is promoted when the building frees, and THEN the engine pays\n");
    UqFinishRunning();
    ScUpgQueueOnTick(UqBuilding());
    Check("the engine started the second", g_uqStarted, 2);
    Check("it is now the running upgrade", (long long)*UqUpgField(), UQ_UPG_B);
    Check("the plugin holds nothing", UqQueued(), 0);
    Check("paid EXACTLY twice, once each", (long long)*UqMinerals(), 1000 - 2 * 100);

    printf("\n    FIFO across BOTH opcodes: upgrade, tech, upgrade -- in that order\n");
    UqBegin(8, 1000, 1000);
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_A);     // starts
    UqPress(SC_UPGQ_KIND_TECH,    UQ_TECH_A);    // held
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_B);     // held
    Check("two are held", UqQueued(), 2);
    Check("first held is the TECH", ScUpgQueueKindAt(UqBuilding(), 0), SC_UPGQ_KIND_TECH);
    Check("second held is an UPGRADE", ScUpgQueueKindAt(UqBuilding(), 1), SC_UPGQ_KIND_UPGRADE);
    UqFinishRunning(); ScUpgQueueOnTick(UqBuilding());
    Check("the TECH went first, into its own field", (long long)*UqTechField(), UQ_TECH_A);
    Check("and the upgrade field is idle", (long long)*UqUpgField(), (long long)SC_UPGRADE_NONE);
    UqFinishRunning(); ScUpgQueueOnTick(UqBuilding());
    Check("then the upgrade", (long long)*UqUpgField(), UQ_UPG_B);
    Check("three starts in all", g_uqStarted, 3);
    Check("three costs, no more", (long long)*UqMinerals(), 1000 - 3 * 100);

    printf("\n    the CAP is the plugin's, and past it a command is refused not lost\n");
    UqBegin(3, 5000, 5000);            // 1 running + 2 held
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_A);
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_B);
    UqPress(SC_UPGQ_KIND_TECH,    UQ_TECH_A);
    Check("two held, which is the cap", UqQueued(), 2);
    Check("the card would stop offering here",
          ScUpgQueueShouldUnblock(UqBuilding()) ? 1 : 0, 0);
    UqPress(SC_UPGQ_KIND_UPGRADE, 5);  // one past the cap
    Check("it was NOT queued", UqQueued(), 2);
    Check("it was NOT started either", g_uqStarted, 1);
    Check("and it was counted as refused",
          ScUpgQueueStat(SC_UPGQ_STAT_REFUSED_FULL), 1);
    Check("only the running one was ever paid for", (long long)*UqMinerals(), 5000 - 100);

    printf("\n    below the cap the card IS unblocked -- the negative half of that pair\n");
    UqBegin(8, 1000, 1000);
    Check("an IDLE building is never unblocked (it needs no help)",
          ScUpgQueueShouldUnblock(UqBuilding()) ? 1 : 0, 0);
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_A);
    Check("a BUSY building with room is unblocked",
          ScUpgQueueShouldUnblock(UqBuilding()) ? 1 : 0, 1);
    Check("a unit that is not a building never is",
          (*(DWORD*)(FakeUnit(2) + SC_CUNIT_OFF_FLAGS) = 0,
           ScUpgQueueShouldUnblock(FakeUnit(2)) ? 1 : 0), 0);

    printf("\n    CANCEL takes the plugin's TAIL, refunds nothing, and stops being ours\n");
    UqBegin(8, 1000, 1000);
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_A);
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_B);
    UqPress(SC_UPGQ_KIND_TECH,    UQ_TECH_A);
    Check("two held", UqQueued(), 2);
    Check("the first cancel is consumed by the plugin",
          ScUpgQueueOnCancel(UqBuilding()) ? 1 : 0, 1);
    Check("and it took the NEWEST", UqQueued(), 1);
    Check("which leaves the older one", ScUpgQueueIdAt(UqBuilding(), 0), UQ_UPG_B);
    // Nothing was paid for a held item, so a cancel must move NO money. This is the
    // assertion that would fail loudest if the design ever charged at queue time
    // without also refunding here.
    Check("no money moved on the cancel", (long long)*UqMinerals(), 1000 - 100);
    Check("the second cancel is ours too", ScUpgQueueOnCancel(UqBuilding()) ? 1 : 0, 1);
    Check("now the plugin holds nothing", UqQueued(), 0);
    // ... and with nothing held the press belongs to the engine again, which is what
    // makes "cancel eventually stops the RUNNING one" true.
    Check("so the next cancel falls through to vanilla",
          ScUpgQueueOnCancel(UqBuilding()) ? 1 : 0, 0);
    Check("still only one payment in the whole sequence", (long long)*UqMinerals(), 1000 - 100);

    printf("\n    a player who cannot pay WAITS -- the item is kept, not dropped\n");
    UqBegin(8, 250, 250);              // enough for two at 100, not three
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_A);
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_B);
    UqPress(SC_UPGQ_KIND_TECH,    UQ_TECH_A);
    UqFinishRunning(); ScUpgQueueOnTick(UqBuilding());
    Check("the second started", g_uqStarted, 2);
    Check("balance is down to 50", (long long)*UqMinerals(), 50);
    UqFinishRunning(); ScUpgQueueOnTick(UqBuilding());
    Check("the third could NOT start", g_uqStarted, 2);
    Check("but it is still queued, not lost", UqQueued(), 1);
    Check("and nothing was spent trying", (long long)*UqMinerals(), 50);
    Check("the wait was counted",
          ScUpgQueueStat(SC_UPGQ_STAT_WAITING_COST) > 0 ? 1 : 0, 1);
    *UqMinerals() = 500; *UqGas() = 500;          // income arrives
    ScUpgQueueOnTick(UqBuilding());
    Check("and it starts as soon as the player can pay", g_uqStarted, 3);
    Check("paying exactly its own cost, once", (long long)*UqMinerals(), 400);

    printf("\n    an item the ENGINE's gate refuses is dropped, and costs nothing\n");
    UqBegin(8, 1000, 1000);
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_A);
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_B);
    g_uqGateRefuse = UQ_UPG_B;
    UqFinishRunning(); ScUpgQueueOnTick(UqBuilding());
    Check("it was not started", g_uqStarted, 1);
    Check("it was dropped rather than retried forever", UqQueued(), 0);
    Check("counted as a gate refusal", ScUpgQueueStat(SC_UPGQ_STAT_REFUSED_GATE), 1);
    Check("and no money moved", (long long)*UqMinerals(), 1000 - 100);

    printf("\n    a building that DIES simply forgets its queue -- there is nothing to refund\n");
    UqBegin(8, 1000, 1000);
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_A);
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_B);
    Check("one held", UqQueued(), 1);
    {
        DWORD before = *UqMinerals();
        DWORD gasBefore = *UqGas();
        *(DWORD*)(UqBuilding() + SC_CUNIT_OFF_HITPOINTS) = 0;   // dead
        ScUpgQueueOnTick(FakeUnit(1));   // any tick collects garbage
        Check("the record is gone", ScUpgQueueTrackedBuildings(), 0);
        Check("it was counted as dropped",
              ScUpgQueueStat(SC_UPGQ_STAT_DROPPED), 1);
        // THE POINT OF PAY-AT-START, in one line: a dead building owes the player
        // nothing, because the plugin never took anything.
        Check("and NOT ONE MINERAL came back or went away",
              (long long)*UqMinerals(), (long long)before);
        // This used to read the plugin's own MINERALS_SPENT/GAS_SPENT counters, which no
        // code path could move (issue #66). The gas half is now the same read-back as the
        // mineral half -- the engine's own global, before and after -- so the claim keeps
        // an oracle instead of losing one.
        Check("nor a single unit of gas", (long long)*UqGas(), (long long)gasBefore);
    }

    // -----------------------------------------------------------------------
    // LEVEL STACKING, and the engine rule it must not break.
    //
    // The dangerous version of this feature would suppress upgradeBusy for everybody. The
    // shipped version suppresses it only for the building whose own CUnit+0xC9 already
    // holds that upgrade id -- so the assertions below are a PAIR: the running building
    // may stack, and a SECOND building of the same player may not. A test that only made
    // the first claim would pass for the dangerous version too.
    // -----------------------------------------------------------------------
    printf("\n    LEVEL STACKING: the running building may queue its own next level\n");
    UqBegin(8, 5000, 5000);
    *(BYTE*)((DWORD)FakeRt(SC_VA_UPGRADE_MAX_LEVEL) +
             UQ_PLAYER * SC_UPGRADE_STRIDE_VANILLA + UQ_UPG_A) = 3;
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_A);
    *(BYTE*)(UqBuilding() + SC_CUNIT_OFF_UPGRADE_LEVEL) = 1;   // startUpgrade wrote this
    Check("the building running Weapons may be offered Weapons again",
          ScUpgQueueMaySuppressBusyBit(UqBuilding(), SC_UPGQ_KIND_UPGRADE, UQ_UPG_A) ? 1 : 0, 1);
    // THE GUARD. A second building of the SAME player, idle, must never be offered it --
    // that is the engine rule that stops two buildings paying for one level.
    *(BYTE*)(FakeUnit(1) + SC_CUNIT_OFF_UPGRADE_PROGRESS) = (BYTE)SC_UPGRADE_NONE;
    Check("a SECOND, idle building of the same player may NOT",
          ScUpgQueueMaySuppressBusyBit(FakeUnit(1), SC_UPGQ_KIND_UPGRADE, UQ_UPG_A) ? 1 : 0, 0);
    // ... and neither may a second building researching something ELSE.
    *(BYTE*)(FakeUnit(2) + SC_CUNIT_OFF_UPGRADE_PROGRESS) = (BYTE)UQ_UPG_B;
    Check("nor a second building researching a DIFFERENT upgrade",
          ScUpgQueueMaySuppressBusyBit(FakeUnit(2), SC_UPGQ_KIND_UPGRADE, UQ_UPG_A) ? 1 : 0, 0);
    Check("and a TECH is never level-stacked -- it has no levels",
          ScUpgQueueMaySuppressBusyBit(UqBuilding(), SC_UPGQ_KIND_TECH, UQ_TECH_A) ? 1 : 0, 0);

    printf("\n    ... and it stops at the LEVEL CEILING rather than losing presses\n");
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_A);   // level 2 queued
    Check("one queued", UqQueued(), 1);
    Check("level 3 may still be offered",
          ScUpgQueueMaySuppressBusyBit(UqBuilding(), SC_UPGQ_KIND_UPGRADE, UQ_UPG_A) ? 1 : 0, 1);
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_A);   // level 3 queued
    Check("two queued", UqQueued(), 2);
    Check("but level 4 is NOT -- the ceiling is 3",
          ScUpgQueueMaySuppressBusyBit(UqBuilding(), SC_UPGQ_KIND_UPGRADE, UQ_UPG_A) ? 1 : 0, 0);
    Check("still paid for exactly the ONE that is running",
          (long long)*UqMinerals(), 5000 - 100);

    printf("\n    the stacked levels start in order, each paying its OWN level's price\n");
    // base 100 + factor 75 * currentLevel, which is what the engine's own cost helper
    // computes -- so level 2 costs 175 and level 3 costs 250. The plugin queues an ID, not
    // a price: the level (and therefore the cost) is resolved when the item STARTS.
    {
        DWORD before = *UqMinerals();
        *(BYTE*)((DWORD)FakeRt(SC_VA_UPGRADE_LEVEL) +
                 UQ_PLAYER * SC_UPGRADE_STRIDE_VANILLA + UQ_UPG_A) = 1;   // L1 completed
        UqFinishRunning(); ScUpgQueueOnTick(UqBuilding());
        Check("level 2 started", g_uqStarted, 2);
        Check("and it cost 100 + 75*1", (long long)(before - *UqMinerals()), 175);
        before = *UqMinerals();
        *(BYTE*)((DWORD)FakeRt(SC_VA_UPGRADE_LEVEL) +
                 UQ_PLAYER * SC_UPGRADE_STRIDE_VANILLA + UQ_UPG_A) = 2;   // L2 completed
        UqFinishRunning(); ScUpgQueueOnTick(UqBuilding());
        Check("level 3 started", g_uqStarted, 3);
        Check("and it cost 100 + 75*2", (long long)(before - *UqMinerals()), 250);
        Check("the queue is empty", UqQueued(), 0);
    }

    // -----------------------------------------------------------------------------
    // TASK 042. WHICH SELECTION ARRAY THE RECEIVE HANDLERS READ, same shape as task 038's
    // sc_prodqueue.cpp coverage: the two arrays ABUT (0x006284B8 + 12*4 == 0x006284E8) and
    // agree whenever exactly one building is selected, which is every case this part had
    // until now. Latent here (no upgrade command fans out today), but the trap is the same
    // one 038 found, and this proves the fix reads the SIMULATION's array, not the CLIENT's.
    // -----------------------------------------------------------------------------
    printf("\n    the building a research receive handler acts on comes from the ENGINE's selection array\n");
    UqBegin(8, 1000, 1000);
    {
        DWORD* engineSel = (DWORD*)FakeRt(SC_VA_PLAYERS_SELECTIONS) + UQ_PLAYER * SC_SELECTION_SLOTS;
        DWORD* clientSel = (DWORD*)FakeRt(SC_VA_ACTIVE_PLAYER_SELECTION);
        DWORD* activeId  = (DWORD*)FakeRt(SC_VA_ACTIVE_PLAYER_ID);
        for (int i = 0; i < SC_SELECTION_SLOTS; ++i) { engineSel[i] = 0; clientSel[i] = 0; }
        *activeId = UQ_PLAYER;

        // The simulation holds one building while the client still holds a group -- the
        // shape a fanned-out Select+Upgrade pair would create. The answer is the
        // simulation's building.
        engineSel[0] = FakeUnit(0);
        clientSel[0] = FakeUnit(0);
        clientSel[1] = FakeUnit(1);
        clientSel[2] = FakeUnit(2);
        Check("a group selected, the sim holding one -> that one",
              (long long)ScUpgQueueSoleSelectedUnitForTest(), (long long)FakeUnit(0));

        engineSel[0] = FakeUnit(2);
        Check("a different building in the sim's slot -> that building, not the client's",
              (long long)ScUpgQueueSoleSelectedUnitForTest(), (long long)FakeUnit(2));

        // THE NEGATIVE HALF, and it is the same test the engine makes: two units in the
        // SIMULATION's list means cmdrecvUpgrade/cmdrecvTech do nothing at all.
        engineSel[1] = FakeUnit(3);
        Check("two in the sim's list -> not ours, the engine's own gate refuses too",
              (long long)ScUpgQueueSoleSelectedUnitForTest(), 0LL);
        engineSel[1] = 0;

        // The whole point, stated as an assertion: what the CLIENT holds cannot produce an
        // answer on its own.
        engineSel[0] = 0;
        clientSel[0] = FakeUnit(1);
        Check("the client's list alone answers nothing -- it is not what the engine reads",
              (long long)ScUpgQueueSoleSelectedUnitForTest(), 0LL);
    }

    printf("\n    the feature's OFF switch really is off\n");
    ScUpgQueueTestBegin(NULL, 0, NULL);
    Check("no command is consumed",
          ScUpgQueueOnCommand(UqBuilding(), SC_UPGQ_KIND_UPGRADE, UQ_UPG_A) ? 1 : 0, 0);
    Check("no cancel is consumed", ScUpgQueueOnCancel(UqBuilding()) ? 1 : 0, 0);
    Check("nothing is ever unblocked",
          ScUpgQueueShouldUnblock(UqBuilding()) ? 1 : 0, 0);
    Check("and no level is ever stacked either",
          ScUpgQueueMaySuppressBusyBit(UqBuilding(), SC_UPGQ_KIND_UPGRADE, UQ_UPG_A) ? 1 : 0, 0);
}

static void ExitLogTests(void) {
    Part("the exit log path writes even when the lock is dead-owned");

    char path[MAX_PATH];
    ScLogResolvePath(path, sizeof(path));

    g_lockHeld = CreateEventA(NULL, TRUE, FALSE, NULL);
    g_lockDrop = CreateEventA(NULL, TRUE, FALSE, NULL);
    if (!g_lockHeld || !g_lockDrop) { printf("  FAIL could not create events\n"); ++g_failures; return; }

    HANDLE t = CreateThread(NULL, 0, LockHolderThread, NULL, 0, NULL);
    if (!t) { printf("  FAIL could not start the lock holder\n"); ++g_failures; return; }
    WaitForSingleObject(g_lockHeld, 5000);

    // Exit mode, lock owned by a thread that is not going to give it back.
    int before = CountLines(path, "EXITLOGTEST");
    ScLogSetTryLock();
    DWORD t0 = GetTickCount();
    ScLog("EXITLOGTEST line written with the lock held elsewhere");
    DWORD elapsed = GetTickCount() - t0;
    int after = CountLines(path, "EXITLOGTEST");

    Check("the line reached the log anyway", (long long)(after - before), 1);
    // Bounded: it must not sit on a lock that is never coming back. The cap is
    // SC_LOG_EXIT_WAIT_MS (250); allow generous slack for a loaded machine.
    Check("and it did not block indefinitely (<2s)", (long long)(elapsed < 2000 ? 1 : 0), 1);

    SetEvent(g_lockDrop);
    WaitForSingleObject(t, 5000);
    CloseHandle(t);
    CloseHandle(g_lockHeld);
    CloseHandle(g_lockDrop);

    // Back to normal mode: the ordinary path still takes the lock and still writes.
    ScLogTestClearTryLock();
    before = CountLines(path, "EXITLOGTEST");
    ScLog("EXITLOGTEST normal-mode line");
    after = CountLines(path, "EXITLOGTEST");
    Check("normal mode still writes", (long long)(after - before), 1);
}

// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// [14] the command-card read-back (task 026), driven against a fake card dialog.
// Numbered 14, not 13: task 024 took 13 for the building groups on main, and two parts
// sharing a number makes "which part failed?" unanswerable from a redirected log.
//
// WHY IT NEEDS A TEST AT ALL. This module is the ORACLE for the whole task: the
// answer to "why can nothing drive the Ghost's Cloak" is a single bit it reports,
// control+0x18 & 0x2. An oracle that reports GREYED unconditionally would produce
// exactly the finding the task expects and would be worthless -- AGENTS.md's
// absence-assertions rule in its other direction. So the same walk is driven over
// the same dialog twice, once with the bit set and once with it clear, and both
// readings are required. It also has to REFUSE to fault on a bad Button pointer
// and to terminate on a looped `next`, because it runs on the observer thread
// against a list the game thread is editing.
//
// The module reaches memory through exactly two things -- the module base and the
// reader -- so replacing both runs the whole walk with no StarCraft in the process.
// ---------------------------------------------------------------------------

#define FAKE_CARD_DLG_VA 0x006A0000u
#define FAKE_CARD_BTN_VA 0x006A2000u
#define FAKE_CARD_BAD_VA 0x00780000u   // outside the fake image: unreadable on purpose

static unsigned g_cardReadFails = 0;

// Reads only inside the fake image; anything else fails the way SafeRead fails on
// an uncommitted page in the game.
static bool FakeCardRead(DWORD addr, void* out, size_t n) {
    DWORD lo = (DWORD)(DWORD_PTR)g_fake;
    DWORD hi = lo + FAKE_IMAGE_BYTES;
    if (addr < lo || addr + (DWORD)n > hi) { ++g_cardReadFails; return false; }
    memcpy(out, (const void*)(DWORD_PTR)addr, n);
    return true;
}

static DWORD FakeCardCtl(int i) { return (DWORD)FakeRt(FAKE_CARD_DLG_VA) + 0x100u + (DWORD)i * SC_BINDLG_SIZE; }
static DWORD FakeCardBtn(int i) { return (DWORD)FakeRt(FAKE_CARD_BTN_VA) + (DWORD)i * SC_BUTTON_SIZE; }

// The Ghost's real buttonset, read out of the binary by
// work/scratch/card/dump-buttonsets.ps1 (research/command-card.md 3). Slots 1-5
// are the basic row; slot 7 is Cloak; slot 8 is Lockdown; slot 9 Nuclear Strike.
struct FakeBtnDef { WORD slot; WORD icon; DWORD cond; DWORD act; WORD cparam; WORD aparam; WORD name; WORD dis; };
static const FakeBtnDef kGhostCard[9] = {
    { 1, 0x00E4, 0x004282D0, 0x00424440,  0,  0, 0x0298, 0x0000 },
    { 2, 0x00E5, 0x004282D0, 0x004233F0,  0,  0, 0x0299, 0x0000 },
    { 3, 0x00E6, 0x00428F30, 0x00424380,  0,  0, 0x029A, 0x0000 },
    { 4, 0x00FE, 0x004282D0, 0x00424140,  0,  0, 0x029B, 0x0000 },
    { 5, 0x00FF, 0x004282D0, 0x00423370,  0,  0, 0x029C, 0x0000 },
    { 7, 0x00FC, 0x004293E0, 0x00423730, 10, 10, 0x0158, 0x0163 },  // Personnel Cloaking
    { 7, 0x00FD, 0x00429370, 0x00423270, 10,  0, 0x0159, 0x0000 },  // Decloak (same slot)
    { 8, 0x00F0, 0x004294E0, 0x00423F70,  1,  1, 0x014F, 0x015B },  // Lockdown
    { 9, 0x0137, 0x00428810, 0x00423A40,  0,  0, 0x02AD, 0x02F9 },  // Nuclear Strike
};

// One card control per slot 1..9, laid out the way the engine's own layout
// function leaves them: the button assigned to the control whose index matches
// its slot, slot 6 blanked (no button reaches it), slot 8 hidden (Lockdown not
// researched), slot 9 visible-but-greyed (no silo).
static void BuildFakeCard(bool cloakDisabled) {
    DWORD root = (DWORD)FakeRt(FAKE_CARD_DLG_VA);
    memset((void*)(DWORD_PTR)root, 0, SC_BINDLG_SIZE);
    *(WORD*)(DWORD_PTR)(root + SC_BINDLG_OFF_TYPE) = 0;             // a dialog, not a control
    {
        short* rr = ScDlgBounds(root);
        rr[0] = 500; rr[1] = 358; rr[2] = 639; rr[3] = 479;         // the card's own origin
    }

    for (int i = 0; i < 9; ++i) {
        DWORD c = FakeCardCtl(i);
        int   slot = i + 1;
        memset((void*)(DWORD_PTR)c, 0, SC_BINDLG_SIZE);
        *(WORD*) (DWORD_PTR)(c + SC_BINDLG_OFF_TYPE)   = 2;
        *(short*)(DWORD_PTR)(c + SC_BINDLG_OFF_INDEX)  = (short)slot;
        *(DWORD*)(DWORD_PTR)(c + SC_BINDLG_OFF_PARENT) = root;
        *(DWORD*)(DWORD_PTR)(c + SC_BINDLG_OFF_NEXT)   = (i < 8) ? FakeCardCtl(i + 1) : 0;
        // A 3x3 grid of 33x33 buttons, dialog-relative -- the shape the real card
        // has, so the "compute a slot centre from the read-back" arithmetic the
        // probe does is exercised here rather than only in game.
        short* r = ScDlgBounds(c);
        r[0] = (short)(3 + (i % 3) * 46); r[1] = (short)(6 + (i / 3) * 42);
        r[2] = (short)(r[0] + 32);        r[3] = (short)(r[1] + 32);

        int b = -1;
        for (int k = 0; k < 9; ++k) if (kGhostCard[k].slot == slot) { b = k; break; }
        // slot 6 gets nothing; slot 8's button (Lockdown) is present but hidden.
        if (b < 0) {
            *(DWORD*)(DWORD_PTR)(c + SC_BINDLG_OFF_FLAGS)   = 0;              // hidden, blanked
            *(WORD*) (DWORD_PTR)(c + SC_BINDLG_OFF_GRAPHIC) = 0xFFFF;
            *(DWORD*)(DWORD_PTR)(c + SC_BINDLG_OFF_USER)    = 0;
            continue;
        }

        DWORD bp = FakeCardBtn(b);
        *(WORD*) (DWORD_PTR)(bp + SC_BUTTON_OFF_SLOT)       = kGhostCard[b].slot;
        *(WORD*) (DWORD_PTR)(bp + SC_BUTTON_OFF_ICON)       = kGhostCard[b].icon;
        *(DWORD*)(DWORD_PTR)(bp + SC_BUTTON_OFF_COND)       = kGhostCard[b].cond;
        *(DWORD*)(DWORD_PTR)(bp + SC_BUTTON_OFF_ACTION)     = kGhostCard[b].act;
        *(WORD*) (DWORD_PTR)(bp + SC_BUTTON_OFF_COND_PARAM) = kGhostCard[b].cparam;
        *(WORD*) (DWORD_PTR)(bp + SC_BUTTON_OFF_ACT_PARAM)  = kGhostCard[b].aparam;
        *(WORD*) (DWORD_PTR)(bp + SC_BUTTON_OFF_NAME_STR)   = kGhostCard[b].name;
        *(WORD*) (DWORD_PTR)(bp + SC_BUTTON_OFF_DIS_STR)    = kGhostCard[b].dis;

        DWORD flags = SC_CTRL_FLAG_DRAWN;
        if (slot == 8) {
            flags = 0;                                   // hidden: tech not researched
        } else {
            flags |= SC_CTRL_FLAG_VISIBLE;
            if (slot == 9) flags |= SC_CTRL_FLAG_DISABLED;                    // no silo
            if (slot == 7 && cloakDisabled) flags |= SC_CTRL_FLAG_DISABLED;
        }
        *(DWORD*)(DWORD_PTR)(c + SC_BINDLG_OFF_FLAGS)   = flags;
        *(WORD*) (DWORD_PTR)(c + SC_BINDLG_OFF_GRAPHIC) = kGhostCard[b].icon;
        *(DWORD*)(DWORD_PTR)(c + SC_BINDLG_OFF_USER)    = bp;
    }
    *(DWORD*)(DWORD_PTR)(root + SC_BINDLG_OFF_FIRST_CHILD) = FakeCardCtl(0);

    *(DWORD*)FakeRt(SC_VA_CARD_DIALOG)          = root;
    *(WORD*) FakeRt(SC_VA_CARD_ID)              = 1;                  // the Ghost
    *(WORD*) FakeRt(SC_VA_CARD_OVERRIDE_SEL)    = SC_CARD_ID_NONE;
    *(WORD*) FakeRt(SC_VA_CARD_OVERRIDE_SUB)    = SC_CARD_ID_NONE;
    *(DWORD*)FakeRt(SC_VA_CARD_REFUSE_REASON)   = 8;
    *(DWORD*)FakeRt(SC_VA_ACTIVE_PORTRAIT_UNIT) = FakeUnit(0);
    *(WORD*) (DWORD_PTR)(FakeUnit(0) + SC_CUNIT_OFF_UNIT_ID)   = 1;    // Ghost
    *(WORD*) (DWORD_PTR)(FakeUnit(0) + SC_CUNIT_OFF_BUTTONSET) = 1;
    *(WORD*) (DWORD_PTR)(FakeUnit(0) + SC_CUNIT_OFF_ENERGY)    = 0xC800;  // 200 energy
    *(BYTE*) (DWORD_PTR)(FakeUnit(0) + SC_CUNIT_OFF_PLAYER)    = 0;
    // The buttonset table row the header reports, so "the card id resolves to a
    // real buttonset" is a read and not an inference.
    DWORD e = (DWORD)FakeRt(SC_VA_BUTTONSET_TABLE) + 1u * SC_BUTTONSET_STRIDE;
    *(WORD*) (DWORD_PTR)(e + SC_BUTTONSET_OFF_N)   = 9;
    *(DWORD*)(DWORD_PTR)(e + SC_BUTTONSET_OFF_PTR) = FakeCardBtn(0);
}

// A checksum over the whole fake card region -- the dialog, the controls and the
// Button array. "Read-only" is a claim about behaviour, so it is measured.
static DWORD FakeCardChecksum(void) {
    const BYTE* p = (const BYTE*)FakeRt(FAKE_CARD_DLG_VA);
    DWORD h = 2166136261u;
    for (unsigned i = 0; i < 0x3000u; ++i) { h ^= p[i]; h *= 16777619u; }
    return h;
}

static const ScCardSlot* FindSlot(const ScCardSlot* s, int n, int index) {
    for (int i = 0; i < n; ++i) if (s[i].index == index) return &s[i];
    return NULL;
}

static void CardScanTests(void) {
    Part("the command-card read-back, against a fake card dialog");

    // Every part allocates its own fake image and releases it again (the previous
    // part has already freed g_fake by the time this runs).
    g_fake = (BYTE*)VirtualAlloc(NULL, FAKE_IMAGE_BYTES, MEM_COMMIT | MEM_RESERVE,
                                 PAGE_READWRITE);
    if (!g_fake) { printf("  FAIL could not allocate the fake image\n"); ++g_failures; return; }
    ScCardTestBegin(g_fake, FakeCardRead);

    ScCardHeader hdr;
    ScCardSlot   slots[SC_CARD_SLOTS];

    // --- (a) the Ghost card with Cloak GREYED -------------------------------
    BuildFakeCard(true);
    DWORD before = FakeCardChecksum();
    int n = ScCardSnapshot(&hdr, slots, SC_CARD_SLOTS);
    Check("nine card controls found", n, 9);
    Check("the walk wrote nothing (checksum)", (long long)(FakeCardChecksum() == before), 1);
    Check("header resolved the card dialog", hdr.ok ? 1 : 0, 1);
    Check("card id is the portrait unit's buttonset", hdr.cardId, hdr.portraitSet);
    Check("that buttonset holds nine buttons", hdr.setCount, 9);
    Check("portrait reads as a Ghost", hdr.portraitType, 1);
    Check("visible slots", hdr.shown, 7);
    Check("of which greyed", hdr.greyed, 2);

    const ScCardSlot* s7 = FindSlot(slots, n, 7);
    Check("slot 7 exists", s7 ? 1 : 0, 1);
    if (s7) {
        Check("slot 7 carries a Button record", s7->buttonOk ? 1 : 0, 1);
        Check("slot 7's button is slotted 7",   s7->btnSlot, 7);
        Check("slot 7's condition is the cloak one", (long long)s7->btnCond, 0x004293E0);
        Check("slot 7's action is the cloak one",    (long long)s7->btnAction, 0x00423730);
        Check("slot 7's conditionParam is Personnel Cloaking",
              s7->btnCondParam, SC_TECH_PERSONNEL_CLOAKING);
        Check("slot 7 is visible",  s7->visible ? 1 : 0, 1);
        Check("slot 7 reads GREYED", s7->disabled ? 1 : 0, 1);
        // The click point the probe computes: dialog origin + control rect centre.
        Check("slot 7's centre computes to x",
              hdr.rootRect[0] + (s7->rect[0] + s7->rect[2]) / 2, 500 + (3 + 35) / 2);
        Check("slot 7's centre computes to y",
              hdr.rootRect[1] + (s7->rect[1] + s7->rect[3]) / 2, 358 + (90 + 122) / 2);
    }
    const ScCardSlot* s8 = FindSlot(slots, n, 8);
    Check("slot 8 reads hidden", (s8 && !s8->visible) ? 1 : 0, 1);
    const ScCardSlot* s6 = FindSlot(slots, n, 6);
    Check("slot 6 has no button record", (s6 && !s6->buttonOk) ? 1 : 0, 1);

    // --- (b) THE SAME WALK, Cloak ENABLED -----------------------------------
    // Without this the GREYED reading above proves nothing: a stuck oracle would
    // pass (a) and fail here.
    BuildFakeCard(false);
    n = ScCardSnapshot(&hdr, slots, SC_CARD_SLOTS);
    s7 = FindSlot(slots, n, 7);
    Check("with the bit cleared, slot 7 reads enabled",
          (s7 && s7->visible && !s7->disabled) ? 1 : 0, 1);
    Check("and the greyed count drops to the nuke alone", hdr.greyed, 1);

    // --- (c) an unreadable Button pointer is reported, not followed ----------
    BuildFakeCard(true);
    *(DWORD*)(DWORD_PTR)(FakeCardCtl(6) + SC_BINDLG_OFF_USER) = FAKE_CARD_BAD_VA;
    unsigned failsBefore = g_cardReadFails;
    n = ScCardSnapshot(&hdr, slots, SC_CARD_SLOTS);
    s7 = FindSlot(slots, n, 7);
    Check("a bad Button pointer yields buttonOk=0", (s7 && !s7->buttonOk) ? 1 : 0, 1);
    Check("  and the reader refused it rather than faulting",
          (long long)(g_cardReadFails > failsBefore), 1);
    Check("  the other eight slots still read", n, 9);

    // --- (d) a looped `next` terminates --------------------------------------
    BuildFakeCard(true);
    *(DWORD*)(DWORD_PTR)(FakeCardCtl(8) + SC_BINDLG_OFF_NEXT) = FakeCardCtl(0);
    n = ScCardSnapshot(&hdr, slots, SC_CARD_SLOTS);
    Check("a cyclic child list still returns (bounded walk)", n, 9);

    // --- (e) no card in this process state -----------------------------------
    *(DWORD*)FakeRt(SC_VA_CARD_DIALOG) = 0;
    n = ScCardSnapshot(&hdr, slots, SC_CARD_SLOTS);
    Check("a null card dialog reports not-ok, no slots", (n == 0 && !hdr.ok) ? 1 : 0, 1);

    // --- (f) the per-player tech state, at the ENGINE's indexing ---------------
    // The reason this is here and not left to the game: the whole Ghost result turned
    // on a PTEx writer that used tech-major indexing while the engine uses
    // player-major, and its own read-back agreed with it. So the reader is pinned
    // against literal player*stride+tech offsets, and against the specific pair the
    // bug confused -- player 0 tech 10 versus the byte the old arithmetic would have
    // reached.
    BuildFakeCard(true);
    memset(FakeRt(SC_VA_TECH_AVAILABLE),  0, 12 * SC_TECH_STRIDE_VANILLA);
    memset(FakeRt(SC_VA_TECH_RESEARCHED), 0, 12 * SC_TECH_STRIDE_VANILLA);
    memset(FakeRt(SC_VA_TECH_AVAILABLE_BW),  0, 12 * SC_TECH_STRIDE_BW);
    memset(FakeRt(SC_VA_TECH_RESEARCHED_BW), 0, 12 * SC_TECH_STRIDE_BW);
    // Player 0: Personnel Cloaking available AND researched. Player 2: tech 32 of the
    // BW tail researched -- which is precisely where the old tech-major write for
    // (tech 10, player 0) actually landed, so a reader that still used it would read
    // player 0 as not researched and player 2 as researched.
    *(BYTE*)((DWORD_PTR)FakeRt(SC_VA_TECH_AVAILABLE)  + 0 * SC_TECH_STRIDE_VANILLA + 10) = 1;
    *(BYTE*)((DWORD_PTR)FakeRt(SC_VA_TECH_RESEARCHED) + 0 * SC_TECH_STRIDE_VANILLA + 10) = 1;
    *(BYTE*)((DWORD_PTR)FakeRt(SC_VA_TECH_RESEARCHED_BW) + 2 * SC_TECH_STRIDE_BW + (32 - 24)) = 1;

    ScCardTechState ts;
    Check("player 0's tech state reads", ScCardReadTechState(0, &ts) ? 1 : 0, 1);
    Check("  Personnel Cloaking is researched for player 0", ts.researched[10], 1);
    Check("  and available", ts.available[10], 1);
    Check("  Stim Packs is not", ts.researched[0], 0);
    Check("  and nothing leaked in from the BW tail", ts.researched[32], 0);
    Check("player 2 has the BW tech, player 0 does not",
          (ScCardReadTechState(2, &ts) && ts.researched[32] && !ts.researched[10]) ? 1 : 0, 1);
    Check("an out-of-range player fails closed rather than reading a neighbour",
          ScCardReadTechState(12, &ts) ? 1 : 0, 0);

    ScCardTestEnd();
    Check("the module is off again after the test", ScCardEnabled() ? 1 : 0, 0);

    VirtualFree(g_fake, 0, MEM_RELEASE);
    g_fake = NULL;
}

// ---------------------------------------------------------------------------
// [18] Group production (task 030): the policy that decides whether ONE Train click
// reaches every selected production building.
//
// This is the pure half of the feature and it is worth testing on its own, because it is
// the thing standing between "the fan-out delivers one item per building" and the two
// ways that could go wrong: firing for a selection it was never meant to fire for, and
// paying for a building that cannot build the unit.
//
// ScProdFanDecide is called from TWO places in the shipped plugin -- the button-condition
// detour, which decides whether the player is offered the button at all, and the command
// path, which decides whether the command is fanned out. Testing it once therefore tests
// both, and that shared call is also the guarantee that this feature cannot fire for a
// selection task 024 would not have produced.
// ---------------------------------------------------------------------------
static void ProdFanTests(void) {
    Part("group production: one Train click, one item per building");

    const WORD CC = 106, BARRACKS = 111;
    WORD same4[4]  = { CC, CC, CC, CC };
    WORD mixed3[3] = { CC, BARRACKS, CC };
    WORD one[1]    = { CC };

    printf("\n    the off switch\n");
    ScProdFanTestSetEnabled(false);
    Check("disabled: even the right selection is refused",
          ScProdFanDecide(same4, 4, 1, 3), SC_PRODFAN_OFF);

    ScProdFanTestSetEnabled(true);

    printf("\n    the case this feature exists for\n");
    Check("four same-type buildings, chunk size 1 -> fan out",
          ScProdFanDecide(same4, 4, 1, 3), SC_PRODFAN_OK);
    Check("and two is already a group",
          ScProdFanDecide(same4, 2, 1, 3), SC_PRODFAN_OK);

    printf("\n    the hazard command-opcodes.md 3.2 keeps 0x1F passthrough for\n");
    // A >12 UNIT selection chunks 12 + 1, and that lone tail chunk would train from a
    // unit the player's own selection never could. simSlots is the whole distinction:
    // for a building group EVERY chunk is one building, uniformly.
    Check("a UNIT selection (simSlots 12) is refused however large",
          ScProdFanDecide(same4, 4, 12, 3), SC_PRODFAN_NOT_GROUP);
    Check("and at 13 units too -- the 12+1 split is exactly the trap",
          ScProdFanDecide(same4, 13, 12, 3), SC_PRODFAN_NOT_GROUP);

    printf("\n    one building is vanilla's own path and must stay byte-for-byte stock\n");
    Check("a single building is not fanned out",
          ScProdFanDecide(one, 1, 1, 3), SC_PRODFAN_ONE_BUILDING);
    Check("nor is an empty selection",
          ScProdFanDecide(one, 0, 1, 3), SC_PRODFAN_ONE_BUILDING);

    printf("\n    ACCEPTANCE CRITERION 5: a selection whose buildings differ\n");
    // The task file allows either "refuse" or "queue only where the unit is valid".
    // This refuses, and refuses the WHOLE command rather than the odd building: a partial
    // fan-out would spend the player's minerals on a subset they never chose. It is also
    // belt and braces -- the engine's own requirement interpreter (0x0046E1C0, opcode
    // 0xFF02) compares the required type against the PRODUCER's own CUnit+0x64 and
    // returns -1, so a wrong-kind building would be refused for free even if this line
    // were not here. Two independent refusals, and the plugin's is the outer one.
    Check("a mixed building group is refused outright",
          ScProdFanDecide(mixed3, 3, 1, 3), SC_PRODFAN_MIXED_TYPES);
    WORD mixedTail[3] = { CC, CC, BARRACKS };
    Check("including when the odd one out is last",
          ScProdFanDecide(mixedTail, 3, 1, 3), SC_PRODFAN_MIXED_TYPES);

    printf("\n    the length guard, the same one the fan-out applies to every id\n");
    Check("0x1F at 2 bytes is not the command 0x1F is supposed to be",
          ScProdFanDecide(same4, 4, 1, 2), SC_PRODFAN_BAD_LEN);
    Check("nor at 11", ScProdFanDecide(same4, 4, 1, 11), SC_PRODFAN_BAD_LEN);

    printf("\n    every verdict names itself in the log\n");
    Check("ok",            strcmp(ScProdFanVerdictName(SC_PRODFAN_OK), "ok"), 0);
    Check("mixed types",   strcmp(ScProdFanVerdictName(SC_PRODFAN_MIXED_TYPES),
                                  "mixed-building-types"), 0);
    Check("not a group",   strcmp(ScProdFanVerdictName(SC_PRODFAN_NOT_GROUP),
                                  "not-a-building-group"), 0);

    ScProdFanTestSetEnabled(false);
    Check("the feature is off again after the test",
          ScProdFanDecide(same4, 4, 1, 3), SC_PRODFAN_OFF);
}

// ---------------------------------------------------------------------------
// [16] the status pane's production-queue strip (task 028), against a fake dialog.
//
// WHY IT NEEDS A TEST. This walk is the thing that decides WHERE the run clicks to
// cancel a queued unit, and what it then claims the player could see. Two failure
// modes would both look like a clean result in game:
//
//   * a walk that reports every icon clickable would send the suite clicking an
//     EMPTY queue slot's icon and reading the silence as "the engine refused" --
//     the disabled bit here is the same bit that made task 022's Ghost negative,
//     so it is driven in both directions over the same dialog, exactly as [14] does;
//   * a walk that takes the display index from the control's `index` field rather
//     than from the walk POSITION would agree with the engine on a normal dialog and
//     disagree on a re-ordered one -- and the engine takes one from each
//     (queueLayout by position, statusCtrlActivate by index - 2). So the fake is
//     also built with its child list deliberately out of order, and the reading must
//     make that visible instead of hiding it.
// ---------------------------------------------------------------------------

#define FAKE_STAT_DLG_VA  0x006B0000u
#define FAKE_STAT_USER_VA 0x006B2000u

static DWORD FakeStatCtl(int i)  { return (DWORD)FakeRt(FAKE_STAT_DLG_VA) + 0x100u + (DWORD)i * SC_BINDLG_SIZE; }
static DWORD FakeQIconUser(int i) { return (DWORD)FakeRt(FAKE_STAT_USER_VA) + (DWORD)i * 0x10u; }

// Over the dialog, its controls and the statUser records -- "read-only" is a claim
// about behaviour, so it is measured here the way [14] measures the card's.
static DWORD FakeStatusChecksum(void) {
    const BYTE* p = (const BYTE*)FakeRt(FAKE_STAT_DLG_VA);
    DWORD h = 2166136261u;
    for (unsigned i = 0; i < 0x3000u; ++i) { h ^= p[i]; h *= 16777619u; }
    return h;
}

// `queued` is the logical queue in DISPLAY order (0xE4 = empty), `head` the ring head
// the icons are read through, so the fake exercises the (head + k) % 5 arithmetic
// rather than assuming head == 0. `swap` puts controls 3 and 4 in the wrong order in
// the child list.
static void BuildFakeStatusPane(const WORD* queuedByDisplay, BYTE head, bool swap) {
    DWORD root = (DWORD)FakeRt(FAKE_STAT_DLG_VA);
    memset((void*)(DWORD_PTR)root, 0, SC_BINDLG_SIZE);
    *(WORD*)(DWORD_PTR)(root + SC_BINDLG_OFF_TYPE) = 0;
    {
        short* rr = ScDlgBounds(root);
        rr[0] = 0; rr[1] = 358; rr[2] = 639; rr[3] = 479;      // the console's own origin
    }

    // One leading child the strip does NOT own (index 1), so "find the child with
    // index == 2" is a real search rather than "take the first one".
    DWORD lead = FakeStatCtl(9);
    memset((void*)(DWORD_PTR)lead, 0, SC_BINDLG_SIZE);
    *(WORD*) (DWORD_PTR)(lead + SC_BINDLG_OFF_TYPE)  = 2;
    *(short*)(DWORD_PTR)(lead + SC_BINDLG_OFF_INDEX) = 1;
    *(DWORD*)(DWORD_PTR)(lead + SC_BINDLG_OFF_NEXT)  = FakeStatCtl(0);
    *(DWORD*)(DWORD_PTR)(root + SC_BINDLG_OFF_FIRST_CHILD) = lead;

    for (int k = 0; k < SC_STATQ_SLOTS; ++k) {
        DWORD c = FakeStatCtl(k);
        memset((void*)(DWORD_PTR)c, 0, SC_BINDLG_SIZE);
        *(WORD*) (DWORD_PTR)(c + SC_BINDLG_OFF_TYPE)   = 2;
        *(short*)(DWORD_PTR)(c + SC_BINDLG_OFF_INDEX)  = (short)(SC_STATQ_FIRST_CONTROL + k);
        *(DWORD*)(DWORD_PTR)(c + SC_BINDLG_OFF_PARENT) = root;
        *(DWORD*)(DWORD_PTR)(c + SC_BINDLG_OFF_NEXT)   = (k < SC_STATQ_SLOTS - 1) ? FakeStatCtl(k + 1) : 0;
        short* r = ScDlgBounds(c);
        r[0] = (short)(220 + k * 22); r[1] = 8;
        r[2] = (short)(r[0] + 20);    r[3] = 28;

        DWORD u = FakeQIconUser(k);
        memset((void*)(DWORD_PTR)u, 0, 0x10);
        *(DWORD*)(DWORD_PTR)(c + SC_BINDLG_OFF_USER) = u;

        WORD type = queuedByDisplay[k];
        DWORD flags = SC_CTRL_FLAG_DRAWN | SC_CTRL_FLAG_VISIBLE;
        if (type == SC_BUILD_QUEUE_EMPTY) {
            // What 0x004268D0 writes for an empty slot: a placeholder frame, mode 6,
            // and 0x00418640 -- the DISABLE.
            *(WORD*)(DWORD_PTR)(u + SC_STATUSER_OFF_ICON) = (WORD)(k + 6);
            *(WORD*)(DWORD_PTR)(u + SC_STATUSER_OFF_MODE) = 6;
            flags |= SC_CTRL_FLAG_DISABLED;
            *(WORD*)(DWORD_PTR)(c + SC_BINDLG_OFF_GRAPHIC) = 0;
        } else {
            *(WORD*)(DWORD_PTR)(u + SC_STATUSER_OFF_ICON) = type;
            *(WORD*)(DWORD_PTR)(u + SC_STATUSER_OFF_MODE) = 3;
            *(WORD*)(DWORD_PTR)(u + SC_STATUSER_OFF_TYPE) = type;
            *(WORD*)(DWORD_PTR)(c + SC_BINDLG_OFF_GRAPHIC) = type;
        }
        *(DWORD*)(DWORD_PTR)(c + SC_BINDLG_OFF_FLAGS) = flags;
    }

    if (swap) {
        // Controls 3 and 4 (display 1 and 2) linked the other way round.
        *(DWORD*)(DWORD_PTR)(FakeStatCtl(0) + SC_BINDLG_OFF_NEXT) = FakeStatCtl(2);
        *(DWORD*)(DWORD_PTR)(FakeStatCtl(2) + SC_BINDLG_OFF_NEXT) = FakeStatCtl(1);
        *(DWORD*)(DWORD_PTR)(FakeStatCtl(1) + SC_BINDLG_OFF_NEXT) = FakeStatCtl(3);
    }

    // The building whose ring the icons are drawn from, in SLOT order: display k is
    // slot (head + k) % 5, so the fake writes each display entry into the slot the
    // engine would read it from.
    DWORD unit = FakeUnit(0);
    *(WORD*)(DWORD_PTR)(unit + SC_CUNIT_OFF_UNIT_ID) = 154;              // a Nexus
    *(BYTE*)(DWORD_PTR)(unit + SC_CUNIT_OFF_PLAYER)  = 0;
    *(BYTE*)(DWORD_PTR)(unit + SC_CUNIT_OFF_BUILD_QUEUE_SLOT) = head;
    for (int k = 0; k < SC_BUILD_QUEUE_SLOTS; ++k) {
        *(WORD*)(DWORD_PTR)(unit + SC_CUNIT_OFF_BUILD_QUEUE + (DWORD)((head + k) % 5) * 2) =
            queuedByDisplay[k];
    }

    *(DWORD*)FakeRt(SC_VA_STATDATA_DIALOG)      = root;
    *(DWORD*)FakeRt(SC_VA_ACTIVE_PORTRAIT_UNIT) = unit;
}

// ---------------------------------------------------------------------------
// [19] the queue-overflow indicator (task 033), against a fake status pane.
//
// Two things are decidable here and both are the feature: WHAT the module decides to say
// (the composer is pure), and WHAT IT LEAVES IN THE DIALOG when it says it -- the spliced
// control's own fields, the five icons' statUser records, and the fact that all of it goes
// away again when the queue drops back under.
//
// What is NOT provable offline is that the engine's text routine actually puts ink on the
// dialog surface. That needs a running game, and it is what tools/plugin/test-queue-
// indicator.ps1 asserts (`QIND ... ink=`) -- the same gap that let sc_hudrow's indicator
// pass its own test for weeks while drawing nothing.
// ---------------------------------------------------------------------------

#define FAKE_QIND_DLG_VA 0x006B8000u

// The fake pane holds the five queue icons AND the twelve wireframe buttons, because the
// group line is now placed from the ROW's own rects (task 039) and a fake with one button
// in it would let a placement bug through.
#define QI_BTN_COUNT SC_HUD_BUTTON_COUNT
#define QI_CTL_COUNT (SC_STATQ_SLOTS + QI_BTN_COUNT)

static DWORD QiCtl(int i) { return (DWORD)FakeRt(FAKE_QIND_DLG_VA) + 0x100u + (DWORD)i * SC_BINDLG_SIZE; }
static DWORD QiUser(int i) { return (DWORD)FakeRt(FAKE_QIND_DLG_VA) + 0x800u + (DWORD)i * 0x10u; }
static DWORD QiLabel(int i) { return (DWORD)FakeRt(FAKE_QIND_DLG_VA) + 0x900u + (DWORD)i * 8u; }
static DWORD QiFont(void)  { return (DWORD)FakeRt(FAKE_QIND_DLG_VA) + 0x980u; }
static DWORD QiBits(void)  { return (DWORD)FakeRt(FAKE_QIND_DLG_VA) + 0x2000u; }
static DWORD QiRoot(void) { return (DWORD)FakeRt(FAKE_QIND_DLG_VA); }

// The two GRP handles the engine picks between. Values, not art: this module only ever
// compares them and copies one of them, so a fake pointer into the fake image is exactly
// as much of a GRP as the code under test can tell.
static DWORD QiGrpIcons(void) { return (DWORD)FakeRt(FAKE_QIND_DLG_VA) + 0x990u; }
static DWORD QiGrpBtns(void)  { return (DWORD)FakeRt(FAKE_QIND_DLG_VA) + 0x9A0u; }

// The pane's own geometry, as the live dialog reports it (work/scratch/033 QINDDLG dump,
// and the same numbers again in this task's run): a 270x92 surface, the strip's five icons
// 38x35 with slot 0 above the other four, and the row's twelve buttons in TWO ROWS of six
// -- which is the fact the group line's band depends on.
#define QI_SURF_W 270
#define QI_SURF_H 92
static const short kQiBtnX[6] = { 30, 66, 102, 138, 174, 210 };
static void QiBtnRect(int i, short* r) {
    r[0] = kQiBtnX[i / 2];
    r[1] = (short)((i % 2) ? 45 : 8);
    r[2] = (short)(r[0] + 32);
    r[3] = (short)(r[1] + 33);
}

static unsigned g_qiShows = 0, g_qiHides = 0, g_qiUpdates = 0, g_qiDriverCalls = 0;
static void QiShow(DWORD c)   { ++g_qiShows;   *(DWORD*)(c + SC_BINDLG_OFF_FLAGS) |= SC_CTRL_FLAG_VISIBLE; }
static void QiHide(DWORD c)   { ++g_qiHides;   *(DWORD*)(c + SC_BINDLG_OFF_FLAGS) &= ~(DWORD)SC_CTRL_FLAG_VISIBLE; }
static void QiUpdate(DWORD c) { ++g_qiUpdates; (void)c; }
static void QiOrigDriver(void) { ++g_qiDriverCalls; }

// Root + the five queue icons (ids 2..6) + the twelve wireframe buttons (ids 0x21..0x2C),
// laid out the way the live dialog reports them (work/scratch/033 and 039 QINDDLG dumps).
//
// THE FIVE ICONS START IN THE STATE THE ENGINE'S OWN LAYOUT LEAVES THEM IN, and that means
// all FIVE fields queueLayout writes, not the three this fixture used to model: an occupied
// slot draws from the ICON grp and carries its slot label, an empty one draws the
// placeholder frame FROM THE BUTTON-BORDER GRP and carries no label at all. Task 039's bug
// was leaving that grp behind, and a fake that zeroed the field could not see it happen --
// the old assertions passed on a build that drew the wrong picture for every queued type.
static void BuildFakeQIndPane(int engineLen, WORD type) {
    DWORD root = QiRoot();
    memset((void*)root, 0, SC_BINDLG_SIZE);
    *(WORD*)(root + SC_BINDLG_OFF_TYPE) = 0;
    short* rr = ScDlgBounds(root);
    rr[0] = 138; rr[1] = 388; rr[2] = 407; rr[3] = 479;

    // The dialog's own 8-bit surface, at the offset the draw walk installs. The group
    // line's band is clamped into it, so a fake without one cannot place that line.
    memset((void*)QiBits(), 0, QI_SURF_W * QI_SURF_H);
    *(WORD*) (root + SC_BINDLG_OFF_SURFACE + SC_SURFACE_OFF_W)    = QI_SURF_W;
    *(WORD*) (root + SC_BINDLG_OFF_SURFACE + SC_SURFACE_OFF_H)    = QI_SURF_H;
    *(DWORD*)(root + SC_BINDLG_OFF_SURFACE + SC_SURFACE_OFF_BITS) = QiBits();

    // The engine's two GRP handles and its five slot labels, in the globals the module
    // reads them from.
    *(DWORD*)FakeRt(SC_VA_GRP_CMDICONS) = QiGrpIcons();
    *(DWORD*)FakeRt(SC_VA_GRP_CMDBTNS)  = QiGrpBtns();
    for (int k = 0; k < SC_STATQ_SLOTS; ++k) {
        _snprintf((char*)QiLabel(k), 8, "%d ", k + 1);
        ((DWORD*)FakeRt(SC_VA_STATQ_SLOT_LABELS))[k] = QiLabel(k);
    }
    // A font whose header says 10 pixels -- over the nine that were measured too short.
    memset((void*)QiFont(), 0, 16);
    *(BYTE*)(QiFont() + SC_FONT_OFF_HEIGHT) = 10;
    *(DWORD*)FakeRt(SC_VA_FONT_SMALLEST) = QiFont();

    for (int k = 0; k < SC_STATQ_SLOTS; ++k) {
        DWORD c = QiCtl(k);
        memset((void*)c, 0, SC_BINDLG_SIZE);
        *(WORD*) (c + SC_BINDLG_OFF_TYPE)   = 2;
        *(short*)(c + SC_BINDLG_OFF_INDEX)  = (short)(SC_STATQ_FIRST_CONTROL + k);
        *(DWORD*)(c + SC_BINDLG_OFF_PARENT) = root;
        *(DWORD*)(c + SC_BINDLG_OFF_NEXT)   = QiCtl(k + 1);
        short* r = ScDlgBounds(c);
        if (k == 0) { r[0] = 104; r[1] = 14; }
        else        { r[0] = (short)(104 + (k - 1) * 39); r[1] = 53; }
        r[2] = (short)(r[0] + 38); r[3] = (short)(r[1] + 35);

        DWORD u = QiUser(k);
        memset((void*)u, 0, 0x10);
        *(DWORD*)(c + SC_BINDLG_OFF_USER) = u;
        DWORD flags = SC_CTRL_FLAG_DRAWN | SC_CTRL_FLAG_VISIBLE | SC_CTRL_FONT_SMALLEST;
        if (k < engineLen) {
            *(DWORD*)(u + SC_STATUSER_OFF_GRP)  = QiGrpIcons();
            *(WORD*) (u + SC_STATUSER_OFF_ICON) = type;
            *(WORD*) (u + SC_STATUSER_OFF_MODE) = 3;
            *(WORD*) (u + SC_STATUSER_OFF_TYPE) = type;
            *(DWORD*)(c + SC_BINDLG_OFF_TEXT)   = QiLabel(k);
        } else {
            *(DWORD*)(u + SC_STATUSER_OFF_GRP)  = QiGrpBtns();   // 0x00426A5A/0x00426A63
            *(WORD*) (u + SC_STATUSER_OFF_ICON) = (WORD)(k + 6); // the placeholder frame
            *(WORD*) (u + SC_STATUSER_OFF_MODE) = 6;
            *(DWORD*)(c + SC_BINDLG_OFF_TEXT)   = 0;             // 0x00426A74
            flags |= SC_CTRL_FLAG_DISABLED;                      // 0x00418640
        }
        *(DWORD*)(c + SC_BINDLG_OFF_FLAGS) = flags;
    }
    // The wireframe row: twelve buttons, two rows of six, the shape the band sits under.
    for (int i = 0; i < QI_BTN_COUNT; ++i) {
        DWORD c = QiCtl(SC_STATQ_SLOTS + i);
        memset((void*)c, 0, SC_BINDLG_SIZE);
        *(WORD*) (c + SC_BINDLG_OFF_TYPE)   = 2;
        *(short*)(c + SC_BINDLG_OFF_INDEX)  = (short)(SC_HUD_FIRST_SMALL_BUTTON + i);
        *(DWORD*)(c + SC_BINDLG_OFF_PARENT) = root;
        *(DWORD*)(c + SC_BINDLG_OFF_NEXT)   = (i + 1 < QI_BTN_COUNT)
                                            ? QiCtl(SC_STATQ_SLOTS + i + 1) : 0;
        QiBtnRect(i, ScDlgBounds(c));
        *(DWORD*)(c + SC_BINDLG_OFF_FLAGS) = SC_CTRL_FLAG_VISIBLE;
    }
    *(DWORD*)(root + SC_BINDLG_OFF_FIRST_CHILD) = QiCtl(0);

    *(DWORD*)((DWORD)FakeRt(SC_VA_DEFAULT_INTERACT_TABLE) + SC_CTRL_TYPE_LSTATIC * 4) = 0x33333333u;
    *(DWORD*)((DWORD)FakeRt(SC_VA_DEFAULT_UPDATE_TABLE)   + SC_CTRL_TYPE_LSTATIC * 4) = 0x44444444u;
    *(DWORD*)FakeRt(SC_VA_STATDATA_DIALOG)      = root;
    *(DWORD*)FakeRt(SC_VA_ACTIVE_PORTRAIT_UNIT) = PqBuilding();
    *(BYTE*) FakeRt(SC_VA_CLIENT_SELECTION_COUNT) = 1;
}

// The LAST child of the fake pane, which is where a control has to be to be drawn on top
// of the ones before it (the redraw walk 0x0041C683 takes them head to tail).
static DWORD QiLastChild(void) {
    DWORD last = 0;
    for (DWORD c = *(DWORD*)(QiRoot() + SC_BINDLG_OFF_FIRST_CHILD); c;
         c = *(DWORD*)(c + SC_BINDLG_OFF_NEXT)) last = c;
    return last;
}

static int QiChildren(void) {
    int n = 0;
    for (DWORD c = *(DWORD*)(QiRoot() + SC_BINDLG_OFF_FIRST_CHILD); c && n < 32;
         c = *(DWORD*)(c + SC_BINDLG_OFF_NEXT)) ++n;
    return n;
}

// The indicator, found by walking the LIVE child chain -- never by asking the module where
// it put it. Returns 0 when it is not linked.
static DWORD QiIndicator(void) {
    for (DWORD c = *(DWORD*)(QiRoot() + SC_BINDLG_OFF_FIRST_CHILD); c;
         c = *(DWORD*)(c + SC_BINDLG_OFF_NEXT)) {
        if (*(short*)(c + SC_BINDLG_OFF_INDEX) < 0) return c;
    }
    return 0;
}

static void QueueIndTests(void) {
    Part("the queue-overflow indicator: composer, splice, and the fifth icon");

    g_fake = (BYTE*)VirtualAlloc(NULL, FAKE_IMAGE_BYTES, MEM_COMMIT | MEM_RESERVE,
                                 PAGE_READWRITE);
    if (!g_fake) { printf("  FAIL could not allocate the fake image\n"); ++g_failures; return; }

    printf("\n    the composer, driven directly -- one case per line it can produce\n");
    {
        char t[48];
        ScQueueIndView v;

        memset(&v, 0, sizeof(v)); v.selection = 1; v.engineLen = 3;
        Check("three queued, nothing hidden -> nothing said",
              ScQueueIndCompose(t, sizeof(t), &v), SC_QIND_NONE);
        Check("  and the string is empty", (long long)(t[0] == '\0'), 1);

        memset(&v, 0, sizeof(v)); v.selection = 1; v.engineLen = 4; v.overflow = 1;
        Check("a five-item logical queue fills the strip and says nothing",
              ScQueueIndCompose(t, sizeof(t), &v), SC_QIND_NONE);
        Check("  five icons drawable", ScQueueIndDrawableSlots(&v), 5);

        memset(&v, 0, sizeof(v)); v.selection = 1; v.engineLen = 4; v.overflow = 5;
        Check("nine queued -> \"+4\"", ScQueueIndCompose(t, sizeof(t), &v), SC_QIND_STRIP);
        Check("  the string is exactly that", (long long)(strcmp(t, "+4") == 0), 1);
        Check("  and only five icons are drawable", ScQueueIndDrawableSlots(&v), 5);

        memset(&v, 0, sizeof(v)); v.selection = 1; v.upgrades = 3;
        Check("queued upgrades -> \"+3 upg\"", ScQueueIndCompose(t, sizeof(t), &v),
              SC_QIND_UPGRADE);
        Check("  the string is exactly that", (long long)(strcmp(t, "+3 upg") == 0), 1);

        memset(&v, 0, sizeof(v)); v.selection = 4; v.buildings = 4; v.queued = 12;
        Check("a group -> the group line", ScQueueIndCompose(t, sizeof(t), &v), SC_QIND_GROUP);
        Check("  naming both numbers",
              (long long)(strcmp(t, "4 bldgs  12 queued") == 0), 1);

        memset(&v, 0, sizeof(v)); v.selection = 4; v.buildings = 1; v.queued = 3;
        Check("one producing building in a group -> nothing (vanilla shows it already)",
              ScQueueIndCompose(t, sizeof(t), &v), SC_QIND_NONE);

        memset(&v, 0, sizeof(v)); v.selection = 30; v.buildings = 4; v.queued = 12;
        v.hudPages = 3;
        Check("while the ROW is paging, its own indicator owns the space",
              ScQueueIndCompose(t, sizeof(t), &v), SC_QIND_NONE);
    }

    printf("\n    the frame path: nine queued at one building\n");
    // A real overflow, built the engine's way through the production-queue core: nine
    // Train presses leave the ring at four and the plugin holding five.
    // PQ_TYPE_B (0x07), not PQ_TYPE_A (0x00): the icon assertions below read a unit type
    // out of a statUser record, and a type id of ZERO would also be what an untouched
    // record reads -- the assertion has to be able to fail.
    PqBegin(16, 3000, 500);
    for (int i = 0; i < 9; ++i) PqTrain(PQ_TYPE_B);
    Check("the ring holds four", PqEngineLen(), SC_PRODQ_ENGINE_HOLD);
    Check("the plugin holds five", PqOverflow(), 5);

    BuildFakeQIndPane(SC_PRODQ_ENGINE_HOLD, PQ_TYPE_B);
    ScQueueIndTestBegin(g_fake, &QiShow, &QiHide, &QiUpdate, &QiOrigDriver);
    Check("nothing spliced before the first frame", QiChildren(), QI_CTL_COUNT);
    // THE POSITIVE HALF of the icon assertions below: the fifth slot starts out pointing at
    // the button-border art, because that is what the engine's layout leaves on a slot it
    // drew EMPTY. Without this line "the plugin set the icon GRP" could pass on a fixture
    // that was already holding it.
    Check("the engine left the fifth slot drawing from the PLACEHOLDER grp",
          (long long)(*(DWORD*)(QiUser(4) + SC_STATUSER_OFF_GRP) == QiGrpBtns()), 1);
    Check("  and with no slot label at all",
          (long long)*(DWORD*)(QiCtl(4) + SC_BINDLG_OFF_TEXT), 0);

    ScQueueIndOnFrame();
    Check("the indicator is now linked into the child chain", QiChildren(), QI_CTL_COUNT + 1);
    {
        DWORD ind = QiIndicator();
        Check("  and the walk finds it", ind ? 1 : 0, 1);
        // Z-ORDER, and it is a position in a list rather than a preference. The dialog's
        // redraw walk takes the children head to tail, so the LAST one is the one drawn
        // over the others; at the head -- where this control used to be spliced -- the
        // engine's own controls painted over it in the same frame, every frame.
        Check("  and it is the LAST child, so it is painted over the others, not under",
              (long long)(ind == QiLastChild()), 1);
        if (ind) {
            const char* text = (const char*)*(DWORD*)(ind + SC_BINDLG_OFF_TEXT);
            // Read out of the CONTROL, not out of the module: this is the assertion
            // sc_hudrow's suite was missing.
            Check("  its pszText says \"+4\"", (long long)(text && strcmp(text, "+4") == 0), 1);
            Check("  the engine's visible bit is set on it",
                  (*(DWORD*)(ind + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE) ? 1 : 0, 1);
            Check("  it is a static-text control", (long long)*(WORD*)(ind + SC_BINDLG_OFF_TYPE),
                  (long long)SC_CTRL_TYPE_LSTATIC);
            Check("  drawn by the engine's own handler for that type",
                  (long long)*(DWORD*)(ind + SC_BINDLG_OFF_UPDATE), (long long)0x44444444u);
            Check("  its id is negative, so the CREATE binder skips it",
                  (long long)(*(short*)(ind + SC_BINDLG_OFF_INDEX) < 0), 1);
            short* b = ScDlgBounds(ind);
            // The box has to be TALLER than the font or the engine's own draw refuses,
            // silently (research/status-pane-text.md 3). The in-game ink assertion is what
            // proves the number is big enough; this proves the box was not left flat.
            Check("  the box is at least SC_QIND_BOX_H tall", b[3] - b[1] >= SC_QIND_BOX_H, 1);
            // ... AND wide enough for the string it holds. A box too SHORT draws nothing;
            // a box too NARROW draws a TRUNCATION, which reads as a working feature and is
            // therefore worse. Found live, not here -- see the group case below.
            Check("  and wide enough for the string it holds",
                  (b[2] - b[0]) >= (int)strlen(ScQueueIndCurrentText()) * SC_QIND_CHAR_W ? 1 : 0, 1);
            Check("  and sits inside the anchor icon (id 6)",
                  (long long)(b[0] >= *ScDlgBounds(QiCtl(4)) &&
                              b[2] <= *(short*)(QiCtl(4) + SC_BINDLG_OFF_BOUNDS + 4)), 1);
            // AND THE VERY FIRST SHOW ALREADY HAS A BASELINE. The copy taken on hidden frames
            // needs a splice to exist, and the splice happens on this frame -- so without the
            // second capture site (just before the show) a pane that goes straight from an
            // empty queue to "+4" reports boxDiff=-1 for as long as it stays up, and every
            // suite asserting on it skips instead of measuring. -1 is "no answer"; this must
            // be a number, and offline that number is 0 because nothing paints here.
            Check("  and the first show already has a baseline, so boxDiff answers",
                  (long long)(ScQueueIndBoxDiff(QiRoot()) >= 0), 1);
        }
    }
    Check("the original driver ran first, every frame", (long long)g_qiDriverCalls, 0);

    printf("\n    ... and the FIFTH icon is the ENGINE's to draw now: the phantom bracket\n");
    // Task 066. The hand-fill of the fifth icon is DELETED: the detour on queueLayout
    // (0x004268D0) writes the held item's type into the empty ring slot before the
    // engine's own layout runs and restores 0xE4 the instant it returns, so the engine
    // lays the slot out as occupied with its own code and no disableControl ever fires
    // on it (task 061's defect). Offline there is no engine layout to observe, so what
    // is provable here is the bracket itself -- the writes, the byte-exact restore, the
    // seqlock generation around them -- and that the frame path no longer hand-writes.
    {
        DWORD unit = PqBuilding();
        const BYTE head = *(BYTE*)(unit + SC_CUNIT_OFF_BUILD_QUEUE_SLOT);
        const int  tail = ((int)head + SC_PRODQ_ENGINE_HOLD) % SC_BUILD_QUEUE_SLOTS;
        WORD* slot = (WORD*)(unit + SC_CUNIT_OFF_BUILD_QUEUE + (DWORD)tail * 2);
        Check("the slot behind display 4 is EMPTY before the bracket",
              (long long)*slot, (long long)SC_BUILD_QUEUE_EMPTY);
        const unsigned gen0 = ScQueueIndRingGen();
        Check("  and the generation starts even", (long long)(gen0 & 1), 0);

        Check("apply writes exactly ONE slot (one hole, five held)",
              ScQueueIndPhantomApply(), 1);
        Check("  the engine would now see the OLDEST held item there",
              (long long)*slot, (long long)PQ_TYPE_B);
        Check("  the four real items are untouched",
              (long long)(*(WORD*)(unit + SC_CUNIT_OFF_BUILD_QUEUE + (DWORD)(((int)head + 0) % 5) * 2) == PQ_TYPE_B &&
                          *(WORD*)(unit + SC_CUNIT_OFF_BUILD_QUEUE + (DWORD)(((int)head + 3) % 5) * 2) == PQ_TYPE_B), 1);
        // The seqlock: an observer reading NOW sees an odd generation and retries, which
        // is what keeps a phantom out of every PRODQ/PRODQSEL/STATQ line.
        Check("  the window is OPEN: generation is odd", (long long)(ScQueueIndRingGen() & 1), 1);
        Check("  and the phantom counter moved", (long long)(ScQueueIndStat(SC_QIND_STAT_PHANTOM) > 0), 1);

        ScQueueIndPhantomRestore();
        Check("restore puts the empty sentinel back, byte-exact",
              (long long)*slot, (long long)SC_BUILD_QUEUE_EMPTY);
        Check("  the window is CLOSED: generation even and moved",
              (long long)((ScQueueIndRingGen() & 1) == 0 && ScQueueIndRingGen() != gen0), 1);
        Check("  a second restore is a no-op", (ScQueueIndPhantomRestore(),
              (long long)*slot), (long long)SC_BUILD_QUEUE_EMPTY);

        // A slot the overflow map says is ours but which holds a REAL type is REFUSED and
        // counted, never overwritten. Reachable only with a gap in the ring (occupied
        // slots stopped being contiguous from the head), which the rebalance invariant
        // forbids -- so the counter doubles as that invariant's tripwire.
        WORD* gap = (WORD*)(unit + SC_CUNIT_OFF_BUILD_QUEUE + (DWORD)(((int)head + 3) % 5) * 2);
        const WORD saved = *gap;
        *gap = SC_BUILD_QUEUE_EMPTY;            // ring: B,B,B,_,_ then a foreign item at the tail
        *slot = (WORD)(PQ_TYPE_B + 1);
        const int dirtyBefore = ScQueueIndStat(SC_QIND_STAT_PHANTOM_DIRTY);
        // ScUnitQueueLength counts occupied slots ANYWHERE in the ring, so it reads 4
        // (three real + the foreign tail item) and apply's k=4 names slot head+4 -- the
        // foreign item, exactly the collision the refusal exists for.
        Check("a non-empty slot where the map expects a hole is REFUSED",
              ScQueueIndPhantomApply(), 0);
        Check("  the foreign item survives untouched", (long long)*slot, (long long)(PQ_TYPE_B + 1));
        Check("  and the refusal is counted, not silent",
              (long long)(ScQueueIndStat(SC_QIND_STAT_PHANTOM_DIRTY) - dirtyBefore), 1);
        *gap = saved;                            // put the fixture's ring back
        *slot = SC_BUILD_QUEUE_EMPTY;
    }
    {
        // AND THE DELETED WRITES STAY DELETED. The frame path used to write five fields
        // and clear DISABLED on the fifth icon; every one of those writes is now the
        // engine's, so a frame over the fake pane -- where no engine exists -- must leave
        // the empty-slot layout EXACTLY as the engine's own empty branch left it. This is
        // the regression guard for the hand-fill quietly coming back.
        BuildFakeQIndPane(SC_PRODQ_ENGINE_HOLD, PQ_TYPE_B);
        ScQueueIndTestBegin(g_fake, &QiShow, &QiHide, &QiUpdate, &QiOrigDriver);
        ScQueueIndOnFrame();
        DWORD c = QiCtl(4), u = QiUser(4);
        Check("the frame path no longer writes the fifth icon's mode",
              (long long)*(WORD*)(u + SC_STATUSER_OFF_MODE), 6);
        Check("  nor its grp", (long long)(*(DWORD*)(u + SC_STATUSER_OFF_GRP) == QiGrpBtns()), 1);
        Check("  nor its label", (long long)*(DWORD*)(c + SC_BINDLG_OFF_TEXT), 0);
        Check("  nor its DISABLED bit",
              (*(DWORD*)(c + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_DISABLED) ? 1 : 0, 1);
        Check("  and the four ENGINE icons were not touched either",
              (long long)(*(WORD*)(QiUser(0) + SC_STATUSER_OFF_MODE) == 3 &&
                          *(WORD*)(QiUser(3) + SC_STATUSER_OFF_MODE) == 3 &&
                          *(DWORD*)(QiUser(0) + SC_STATUSER_OFF_GRP) == QiGrpIcons() &&
                          *(DWORD*)(QiCtl(0) + SC_BINDLG_OFF_TEXT) == QiLabel(0)), 1);
    }
    {
        // A settled strip costs nothing: a second frame with the same state re-writes
        // neither the icons nor the text.
        unsigned shows = g_qiShows, updates = g_qiUpdates;
        ScQueueIndOnFrame();
        Check("a settled frame re-shows nothing", (long long)(g_qiShows - shows), 0);
        Check("  and re-draws nothing", (long long)(g_qiUpdates - updates), 0);
    }

    printf("\n    the GROUP line gets a box sized for IT, not for the button it starts on\n");
    // The defect this covers was found in a live run rather than here: the group text is
    // ~17 characters and the wireframe button it anchors to is 34 pixels wide, so clamping
    // the box to the anchor truncated it -- and every assertion above (mode, text, linked,
    // visible, ink>0) still passed, because a truncated string is still ink. The strip's
    // "+N" is short and stays inside its icon; the row's line may run across buttons, which
    // is why leaving it repaints the whole row.
    {
        // Two producing buildings in the engine's own selection is what GROUP mode needs.
        DWORD* g = (DWORD*)FakeRt(SC_VA_CLIENT_SELECTION_GROUP);
        for (int i = 0; i < 12; ++i) g[i] = 0;
        g[0] = PqBuilding();
        g[1] = FakeUnit(1);
        for (int k = 0; k < SC_BUILD_QUEUE_SLOTS; ++k) {
            *(WORD*)(FakeUnit(1) + SC_CUNIT_OFF_BUILD_QUEUE + (DWORD)k * 2) =
                (k < 2) ? (WORD)PQ_TYPE_B : (WORD)SC_BUILD_QUEUE_EMPTY;
        }
        *(BYTE*)FakeRt(SC_VA_CLIENT_SELECTION_COUNT) = 2;
        ScQueueIndOnFrame();
        Check("the indicator is in GROUP mode", ScQueueIndCurrentMode(), SC_QIND_GROUP);
        DWORD ind = QiIndicator();
        if (ind) {
            short* b = ScDlgBounds(ind);
            const char* text = (const char*)*(DWORD*)(ind + SC_BINDLG_OFF_TEXT);
            int need = (int)strlen(text) * SC_QIND_CHAR_W;
            printf("      box=(%d,%d,%d,%d) for \"%s\" (needs %d px)\n",
                   b[0], b[1], b[2], b[3], text, need);
            Check("  its box is wider than the 32px button the row starts with",
                  (b[2] - b[0]) > 32 ? 1 : 0, 1);
            Check("  and wide enough for the whole string", (b[2] - b[0]) >= need ? 1 : 0, 1);
            // BELOW THE ROW, not on it. The user could not read this line because it was
            // drawn in the icons' own rectangles; the fix is a place of its own, computed
            // from the buttons' live bounds -- so what this asserts is that the box clears
            // EVERY one of the twelve, not merely the one it is anchored to.
            short lowest = 0;
            int overlaps = 0;
            for (int i = 0; i < QI_BTN_COUNT; ++i) {
                short r[4];
                QiBtnRect(i, r);
                if (r[3] > lowest) lowest = r[3];
                if (b[0] < r[2] && b[2] > r[0] && b[1] < r[3] && b[3] > r[1]) ++overlaps;
            }
            Check("  it starts below the LOWEST button of the row, all twelve considered",
                  b[1] >= lowest ? 1 : 0, 1);
            Check("  and overlaps none of them", (long long)overlaps, 0);
            Check("  and stays inside the dialog's own surface",
                  (b[2] <= QI_SURF_W && b[3] <= QI_SURF_H) ? 1 : 0, 1);
            // The height rule the engine's string draw applies, checked against the font
            // header the fixture set (10): a box shorter than the font draws NOTHING.
            Check("  and is at least as tall as the font", (b[3] - b[1]) >= 10, 1);
        }

        // ... and when the band cannot hold the font, the line is REFUSED rather than
        // written into a box the engine will silently decline to draw. A 30-pixel font is
        // not a real one; it is the smallest change that makes the space too small, and it
        // proves the refusal exists rather than assuming the band is always big enough.
        {
            *(BYTE*)(QiFont() + SC_FONT_OFF_HEIGHT) = 30;
            ScQueueIndOnFrame();
            Check("a font too tall for the band suppresses the group line",
                  ScQueueIndCurrentMode(), SC_QIND_NONE);
            Check("  and the control is not left showing",
                  (long long)(ScQueueIndIsShown() ? 1 : 0), 0);
            *(BYTE*)(QiFont() + SC_FONT_OFF_HEIGHT) = 10;
            ScQueueIndOnFrame();
            Check("  and it comes back when the font fits again",
                  ScQueueIndCurrentMode(), SC_QIND_GROUP);
        }

        *(BYTE*)FakeRt(SC_VA_CLIENT_SELECTION_COUNT) = 1;
        for (int i = 0; i < 12; ++i) g[i] = 0;
        ScQueueIndOnFrame();
    }

    printf("\n    the queue drains: the text goes away and the control is hidden again\n");
    // Cancel the five held items the way the card's Cancel button does.
    for (int i = 0; i < 5; ++i) ScProdQueueOnCancel(PqBuilding(), SC_CANCEL_TRAIN_LAST);
    Check("the plugin holds nothing", PqOverflow(), 0);
    ScQueueIndOnFrame();
    {
        DWORD ind = QiIndicator();
        Check("the control is still linked (it is ours, and cheap)", ind ? 1 : 0, 1);
        Check("  but the engine's visible bit is CLEAR",
              ind && (*(DWORD*)(ind + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE) ? 1 : 0, 0);
        Check("  and the module says it is showing nothing", ScQueueIndCurrentMode(),
              SC_QIND_NONE);
    }

    printf("\n    boxDiff: the box measured against a copy of itself with none of ours in it\n");
    // THE ORACLE EVERY PIXEL CLAIM IN THIS MODULE NOW RESTS ON, and the reason it is a
    // DIFFERENCE and not a count. `ink` inside the indicator's box counts THE PANE'S OWN ART:
    // this task's first live run read 448 of 448 bytes set inside that box, and 1330 of 1330
    // over a queue icon, before anything of ours had been drawn. So `ink > 0` is true whatever
    // the plugin does, and the suites that asserted it could not fail. What CAN fail is the
    // same rect compared against a copy of it taken while the indicator was hidden.
    {
        DWORD  ind = QiIndicator();
        short* ib  = ScDlgBounds(ind);
        short  was[4] = { ib[0], ib[1], ib[2], ib[3] };
        BYTE*  px  = (BYTE*)QiBits();

        // The drain above hid the control ON THE LAST FRAME, and no copy is taken on that
        // frame (see below), so this is the frame that takes one.
        ScQueueIndOnFrame();
        Check("with nothing of ours on the surface, the box differs from its copy by nothing",
              ScQueueIndBoxDiff(QiRoot()), 0);

        // Seven bytes inside the box -- what a drawn glyph looks like to this probe.
        for (int i = 0; i < 7; ++i) px[(was[1] + 1) * QI_SURF_W + was[0] + i] = (BYTE)(0x50 + i);
        Check("  bytes written inside the box are counted, one for one",
              ScQueueIndBoxDiff(QiRoot()), 7);

        // A copy of a DIFFERENT rect is not a copy of this one. -1 says so; a count would be
        // a number about the wrong pixels, which is worse than no number (AGENTS.md, task 030).
        ib[0] = (short)(was[0] + 1); ib[2] = (short)(was[2] + 1);
        Check("  a box that has MOVED reports -1 rather than a count against the wrong rect",
              ScQueueIndBoxDiff(QiRoot()), -1);
        ib[0] = was[0]; ib[2] = was[2];
        for (int i = 0; i < 7; ++i) px[(was[1] + 1) * QI_SURF_W + was[0] + i] = 0;

        // THE FRAME THE COPY MUST NOT BE TAKEN ON. Hiding only marks the region dirty -- the
        // paint is the dialog's own redraw walk, which has not run when ScQueueIndOnFrame
        // returns -- so on that one frame the surface still holds OUR OWN line. A copy taken
        // then would make the next boxDiff read 0 with the text plainly on the screen: a
        // check that fails at random, which AGENTS.md rates no better than one that cannot
        // fail. The show below takes its own copy first (the surface is clean here), and the
        // seven bytes are written AFTER it, standing in for the line the engine draws.
        for (int i = 0; i < 5; ++i) PqTrain(PQ_TYPE_B);
        ScQueueIndOnFrame();
        Check("the indicator comes back for the same queue", ScQueueIndCurrentMode(),
              SC_QIND_STRIP);
        Check("  in the same box, so the same copy still applies",
              (long long)(ib[0] == was[0] && ib[1] == was[1] &&
                          ib[2] == was[2] && ib[3] == was[3]), 1);
        for (int i = 0; i < 7; ++i) px[(was[1] + 1) * QI_SURF_W + was[0] + i] = (BYTE)(0x50 + i);
        Check("  and what is drawn into the box while it is up is ours",
              ScQueueIndBoxDiff(QiRoot()), 7);

        for (int i = 0; i < 5; ++i) ScProdQueueOnCancel(PqBuilding(), SC_CANCEL_TRAIN_LAST);
        ScQueueIndOnFrame();                       // the frame it hides on
        Check("the frame it HIDES on takes no copy, so our bytes are still counted as ours",
              ScQueueIndBoxDiff(QiRoot()), 7);
        ScQueueIndOnFrame();                       // the next one does
        Check("  and the frame after it does take one, so the box reads clean again",
              ScQueueIndBoxDiff(QiRoot()), 0);

        for (int i = 0; i < 7; ++i) px[(was[1] + 1) * QI_SURF_W + was[0] + i] = 0;
    }

    printf("\n    with the feature OFF nothing is spliced and nothing is written\n");
    {
        PqBegin(16, 3000, 500);
        for (int i = 0; i < 9; ++i) PqTrain(PQ_TYPE_B);
        BuildFakeQIndPane(SC_PRODQ_ENGINE_HOLD, PQ_TYPE_B);
        ScQueueIndTestBegin(NULL, &QiShow, &QiHide, &QiUpdate, &QiOrigDriver);  // disabled
        unsigned shows = g_qiShows;
        ScQueueIndOnFrame();
        ScQueueIndOnFrame();
        Check("no child was added", QiChildren(), QI_CTL_COUNT);
        Check("no control was shown", (long long)(g_qiShows - shows), 0);
        Check("display 4 is still the engine's greyed placeholder",
              (*(DWORD*)(QiCtl(4) + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_DISABLED) ? 1 : 0, 1);
        Check("  still drawing the placeholder frame, not a unit",
              (long long)*(WORD*)(QiUser(4) + SC_STATUSER_OFF_MODE), 6);
        Check("  out of the placeholder art, untouched",
              (long long)(*(DWORD*)(QiUser(4) + SC_STATUSER_OFF_GRP) == QiGrpBtns()), 1);
    }

    ScQueueIndTestBegin(NULL, NULL, NULL, NULL, NULL);
    ScProdQueueTestBegin(NULL, SC_PRODQ_DEFAULT_MAX);
    VirtualFree(g_fake, 0, MEM_RELEASE);
    g_fake = NULL;
}

// ---------------------------------------------------------------------------
// [21] task 037: SC_QIND_UPGRADE through the FRAME PATH, not just the composer.
//
// QueueIndTests above drives ScQueueIndCompose directly for the upgrade case ("queued
// upgrades -> \"+3 upg\"") and stops there -- it never calls ScQueueIndOnFrame for that
// mode the way it does for STRIP and GROUP. That gap is exactly what let this ship: the
// composer is pure and cannot see AnchorFor(), which is the function that decides whether
// the frame path gets a control to splice the text onto at all. AnchorFor had a case for
// SC_QIND_STRIP and one for SC_QIND_GROUP and none for SC_QIND_UPGRADE, so it fell through
// to `return 0`, and ScQueueIndOnFrame reads a null anchor as "nothing to show" and resets
// the mode to SC_QIND_NONE before a splice is even attempted -- on every building, not just
// an Engineering Bay, because neither AnchorFor nor the mode it is given ever look at the
// unit's type. The user: "i do not see upgrade queue - tested on terran engineering bay".
// ---------------------------------------------------------------------------
static void UpgQueueIndTests(void) {
    Part("the queue indicator shows QUEUED UPGRADES through the real frame path (task 037)");

    g_fake = (BYTE*)VirtualAlloc(NULL, FAKE_IMAGE_BYTES, MEM_COMMIT | MEM_RESERVE,
                                 PAGE_READWRITE);
    if (!g_fake) { printf("  FAIL could not allocate the fake image\n"); ++g_failures; return; }

    // The same fake status pane QueueIndTests drives, with an EMPTY ring: a building that
    // is researching is not training anything, so every one of the five queue icons starts
    // in the engine's own greyed placeholder state, same as a real Engineering Bay's.
    BuildFakeQIndPane(0, 0);
    ScQueueIndTestBegin(g_fake, &QiShow, &QiHide, &QiUpdate, &QiOrigDriver);

    // One running (the engine's own slot) plus two held -- "2+ upgrades queued", the
    // user's own words, and a mixed upgrade/tech pair so this cannot be mistaken for a
    // fixture that only ever holds one kind.
    UqBegin(8, 5000, 5000);
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_A);   // starts -- the engine's own slot
    UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_B);   // held
    UqPress(SC_UPGQ_KIND_TECH,    UQ_TECH_A);  // held
    Check("the plugin is holding two", UqQueued(), 2);

    Check("nothing spliced before the first frame", QiChildren(), QI_CTL_COUNT);
    ScQueueIndOnFrame();

    // THE ASSERTIONS QueueIndTests NEVER MADE for this mode -- the ones that actually ask
    // whether the player would see anything, rather than what the composer intended.
    Check("the frame path settles on UPGRADE mode", ScQueueIndCurrentMode(), SC_QIND_UPGRADE);
    Check("the indicator is linked into the dialog's child chain",
          ScQueueIndIsSpliced() ? 1 : 0, 1);
    Check("and the engine's own visible bit is set on it", ScQueueIndIsShown() ? 1 : 0, 1);
    {
        DWORD ind = QiIndicator();
        Check("the walk finds it", ind ? 1 : 0, 1);
        if (ind) {
            const char* text = (const char*)*(DWORD*)(ind + SC_BINDLG_OFF_TEXT);
            Check("its pszText says \"+2 upg\"",
                  (long long)(text && strcmp(text, "+2 upg") == 0), 1);
            short* b = ScDlgBounds(ind);
            Check("the box is at least SC_QIND_BOX_H tall", b[3] - b[1] >= SC_QIND_BOX_H, 1);
            Check("and wide enough for the string it holds",
                  (b[2] - b[0]) >= (int)strlen(ScQueueIndCurrentText()) * SC_QIND_CHAR_W ? 1 : 0, 1);
            // ... which on the LIVE pane means sliding left off icon 6's own start: the
            // icon begins at x=231 of a 270-wide surface and "+2 upg" needs 42px, so a box
            // clamped to the surface edge would have held 38 and cut the string. The fake
            // only started saying so once it carried the real surface (task 039).
            Check("and it stays inside the dialog's surface",
                  (b[2] <= QI_SURF_W) ? 1 : 0, 1);
        }
    }

    // The queue drains back to nothing running or held: the indicator must go away, the
    // same as the STRIP case above -- this mode is not a one-way splice.
    UqFinishRunning();
    ScUpgQueueOnTick(UqBuilding());     // promotes UQ_UPG_B into the engine's own slot
    UqFinishRunning();
    ScUpgQueueOnTick(UqBuilding());     // promotes UQ_TECH_A
    UqFinishRunning();
    ScUpgQueueOnTick(UqBuilding());     // nothing left to promote -- building goes idle
    Check("the plugin holds nothing now", UqQueued(), 0);
    ScQueueIndOnFrame();
    Check("the indicator says NONE again", ScQueueIndCurrentMode(), SC_QIND_NONE);
    Check("and the engine's visible bit is clear",
          ScQueueIndIsShown() ? 1 : 0, 0);

    ScQueueIndTestBegin(NULL, NULL, NULL, NULL, NULL);
    ScUpgQueueTestBegin(NULL, SC_UPGQ_DEFAULT_MAX, NULL);
    VirtualFree(g_fake, 0, MEM_RELEASE);
    g_fake = NULL;
}

static void StatusStripTests(void) {
    Part("the status pane's production-queue strip, against a fake dialog");

    g_fake = (BYTE*)VirtualAlloc(NULL, FAKE_IMAGE_BYTES, MEM_COMMIT | MEM_RESERVE,
                                 PAGE_READWRITE);
    if (!g_fake) { printf("  FAIL could not allocate the fake image\n"); ++g_failures; return; }
    ScCardTestBegin(g_fake, FakeCardRead);

    ScStatusHeader hdr;
    ScStatusSlot   slots[SC_STATQ_SLOTS];

    // --- (a) three Probes queued, two empty slots, head NOT at zero -----------
    const WORD PROBE = 64;
    WORD q3[SC_STATQ_SLOTS] = { PROBE, PROBE, PROBE, SC_BUILD_QUEUE_EMPTY, SC_BUILD_QUEUE_EMPTY };
    BuildFakeStatusPane(q3, 3, false);
    DWORD before = FakeStatusChecksum();
    int n = ScStatusSnapshot(&hdr, slots, SC_STATQ_SLOTS);
    Check("five queue icons found", n, SC_STATQ_SLOTS);
    Check("the header resolved the status dialog", hdr.ok ? 1 : 0, 1);
    Check("the walk wrote nothing (checksum)",
          (long long)(FakeStatusChecksum() == before), 1);
    Check("the portrait unit's ring was readable", hdr.queueOk ? 1 : 0, 1);
    Check("head reads back", hdr.head, 3);
    Check("all five icons are visible", hdr.shown, SC_STATQ_SLOTS);
    // THE HEADLINE: only the three occupied ones can be clicked at all.
    Check("only the three OCCUPIED icons are clickable", hdr.clickable, 3);
    for (int k = 0; k < 3; ++k) {
        Check("  an occupied icon is enabled", slots[k].disabled ? 1 : 0, 0);
        Check("  and draws the queued unit type", slots[k].userIcon, PROBE);
        Check("  which is the type in the ring at (head + k) % 5", slots[k].queueType, PROBE);
        Check("  its control index is display + 2", slots[k].index, k + SC_STATQ_FIRST_CONTROL);
    }
    Check("the first empty icon is GREYED", slots[3].disabled ? 1 : 0, 1);
    Check("  its statUser mode is the empty one", slots[3].userMode, 6);
    Check("  and its ring slot really is empty", slots[3].queueType, SC_BUILD_QUEUE_EMPTY);
    // The click point the suite computes, the same sum as a card slot.
    Check("display 1's centre computes to x",
          hdr.rootRect[0] + (slots[1].rect[0] + slots[1].rect[2]) / 2, 0 + (242 + 262) / 2);
    Check("display 1's centre computes to y",
          hdr.rootRect[1] + (slots[1].rect[1] + slots[1].rect[3]) / 2, 358 + (8 + 28) / 2);

    // --- (b) THE OTHER DIRECTION: a full queue, nothing greyed ----------------
    // Without this, (a)'s "two are greyed" proves nothing -- an oracle that always
    // said GREYED would pass it.
    WORD q5[SC_STATQ_SLOTS] = { PROBE, PROBE, PROBE, PROBE, PROBE };
    BuildFakeStatusPane(q5, 0, false);
    n = ScStatusSnapshot(&hdr, slots, SC_STATQ_SLOTS);
    Check("with five queued, every icon is clickable", hdr.clickable, SC_STATQ_SLOTS);
    Check("  and none reads GREYED", hdr.shown - hdr.clickable, 0);

    // --- (c) an empty queue: the strip is up, nothing can be clicked ----------
    WORD q0[SC_STATQ_SLOTS] = { SC_BUILD_QUEUE_EMPTY, SC_BUILD_QUEUE_EMPTY, SC_BUILD_QUEUE_EMPTY,
                                SC_BUILD_QUEUE_EMPTY, SC_BUILD_QUEUE_EMPTY };
    BuildFakeStatusPane(q0, 2, false);
    n = ScStatusSnapshot(&hdr, slots, SC_STATQ_SLOTS);
    Check("an empty queue still reports five icons", n, SC_STATQ_SLOTS);
    Check("  none of which is clickable", hdr.clickable, 0);

    // --- (d) a re-ordered child list is VISIBLE, not silently absorbed --------
    // The engine takes the display index from the walk position and the payload from
    // index - 2. If those ever disagree the suite must see it here.
    BuildFakeStatusPane(q3, 3, true);
    n = ScStatusSnapshot(&hdr, slots, SC_STATQ_SLOTS);
    Check("the swapped list still yields five icons", n, SC_STATQ_SLOTS);
    Check("display 1 now carries control index 4, not 3", slots[1].index, 4);
    Check("  so `index == display + 2` is FALSE and a run can catch it",
          (long long)(slots[1].index == slots[1].display + SC_STATQ_FIRST_CONTROL), 0);

    // --- (e) an unreadable statUser is reported, not followed ------------------
    BuildFakeStatusPane(q3, 3, false);
    *(DWORD*)(DWORD_PTR)(FakeStatCtl(1) + SC_BINDLG_OFF_USER) = FAKE_CARD_BAD_VA;
    unsigned failsBefore = g_cardReadFails;
    n = ScStatusSnapshot(&hdr, slots, SC_STATQ_SLOTS);
    Check("a bad statUser yields userOk=0", slots[1].userOk ? 1 : 0, 0);
    Check("  and the reader refused it rather than faulting",
          (long long)(g_cardReadFails > failsBefore), 1);
    Check("  the other four icons still read", n, SC_STATQ_SLOTS);

    // --- (f) a looped `next` terminates ---------------------------------------
    BuildFakeStatusPane(q3, 3, false);
    *(DWORD*)(DWORD_PTR)(FakeStatCtl(4) + SC_BINDLG_OFF_NEXT) = FakeStatCtl(0);
    n = ScStatusSnapshot(&hdr, slots, SC_STATQ_SLOTS);
    Check("a cyclic child list still returns (bounded walk)", n, SC_STATQ_SLOTS);

    // --- (g) no strip at all ---------------------------------------------------
    BuildFakeStatusPane(q3, 3, false);
    {
        // A dialog whose children carry no index 2: the strip is not up.
        DWORD lead = FakeStatCtl(9);
        *(DWORD*)(DWORD_PTR)(lead + SC_BINDLG_OFF_NEXT) = 0;
        n = ScStatusSnapshot(&hdr, slots, SC_STATQ_SLOTS);
        Check("no icon control means no slots, but the dialog still reports ok",
              (n == 0 && hdr.ok) ? 1 : 0, 1);
    }
    *(DWORD*)FakeRt(SC_VA_STATDATA_DIALOG) = 0;
    n = ScStatusSnapshot(&hdr, slots, SC_STATQ_SLOTS);
    Check("a null status dialog reports not-ok, no slots", (n == 0 && !hdr.ok) ? 1 : 0, 1);

    ScCardTestEnd();
    VirtualFree(g_fake, 0, MEM_RELEASE);
    g_fake = NULL;
}

// ---------------------------------------------------------------------------
// THE GAME-SESSION EPOCH (task 054; issue #63 and its five siblings in #67)
//
// WHAT MAKES THIS PART DIFFERENT FROM EVERY OTHER ONE HERE, and it is worth stating
// because it is the reason the tests below look strange at first reading: THE FAKE
// MEMORY IS NOT TOUCHED BETWEEN THE TWO GAMES. Not one byte.
//
// That is not a shortcut, it is the fixture. The engine restores a save into its own
// static 1700-slot CUnit table IN PLACE, index by index, 336 bytes each -- so the
// building sits at the same address with the same uniqueness byte, the same owner and
// the same hitpoints it had in the game the record was made in (issue #63, measured in
// game by task 051). "Nothing changed" IS what a load looks like to every per-unit
// check this plugin has. The only thing that moves is the epoch.
//
// So each scenario below runs twice where it can: once with no game start, which is
// the state before this task and must still show the old behaviour, and once with the
// game start, which must show the state gone. Without that pairing these would be
// assertions that cannot fail -- the exact defect AGENTS.md opens with.
// ---------------------------------------------------------------------------
static void SessionEpochTests(void) {
    Part("the game-session epoch: six kinds of cross-game state, one counter");

    if (!g_fake) {
        g_fake = (BYTE*)VirtualAlloc(NULL, FAKE_IMAGE_BYTES, MEM_COMMIT | MEM_RESERVE,
                                     PAGE_READWRITE);
        if (!g_fake) { printf("  FAIL could not allocate the fake image\n"); ++g_failures; return; }
    }

    printf("\n    the counter itself\n");
    ScSessionTestBegin();
    Check("a fresh process is in epoch 1", (long long)ScSessionEpoch(), 1);
    Check("  no game start seen yet", (long long)ScSessionStat(SC_SESSION_STAT_STARTS), 0);
    ScSessionTestNewGame();
    Check("a game start bumps it", (long long)ScSessionEpoch(), 2);
    Check("  and is counted", (long long)ScSessionStat(SC_SESSION_STAT_STARTS), 1);
    ScSessionTestLoad();
    Check("a save load is witnessed", (long long)ScSessionStat(SC_SESSION_STAT_LOADS), 1);
    // The ordering claim the whole design rests on, made checkable: the engine's call
    // graph puts the bump strictly before the deserialiser (sc_session.h), so a load can
    // never be seen in an epoch older than the current one.
    Check("  in the CURRENT epoch, i.e. after the bump, never before it",
          (long long)ScSessionEpochAtLastLoad(), (long long)ScSessionEpoch());

    // -----------------------------------------------------------------------
    // #63 itself: production overflow. This is the offline twin of
    // test-save-load.ps1's arm 6.
    // -----------------------------------------------------------------------
    printf("\n    #63 sc_prodqueue: held items do NOT follow the player into another game\n");
    {
        PqBegin(16, 1000, 500);
        for (int i = 0; i < 8; ++i) PqTrain(PQ_TYPE_A);
        Check("game A: the ring is at the hold", PqEngineLen(), SC_PRODQ_ENGINE_HOLD);
        Check("  and the plugin holds the rest", PqOverflow(), 4);
        const long long spentInGameA = (long long)*PqMinerals();
        const BYTE uniqA   = *(BYTE*)(PqBuilding() + SC_CUNIT_OFF_UNIQUENESS);
        const BYTE playerA = *(BYTE*)(PqBuilding() + SC_CUNIT_OFF_PLAYER);
        const DWORD hpA    = *(DWORD*)(PqBuilding() + SC_CUNIT_OFF_HITPOINTS);

        // THE LOAD. Nothing about the building changes, because nothing about it changes
        // in the real thing either.
        ScSessionTestNewGame();

        Check("the building is at the SAME address", (long long)PqBuilding(),
              (long long)FakeUnit(PQ_BUILDING));
        Check("  same uniqueness byte (CUnit+0xA5)",
              (long long)*(BYTE*)(PqBuilding() + SC_CUNIT_OFF_UNIQUENESS), (long long)uniqA);
        Check("  same owner (CUnit+0x4C)",
              (long long)*(BYTE*)(PqBuilding() + SC_CUNIT_OFF_PLAYER), (long long)playerA);
        Check("  same hitpoints -- so EVERY term of RecordStillLive still passes",
              (long long)*(DWORD*)(PqBuilding() + SC_CUNIT_OFF_HITPOINTS), (long long)hpA);

        Check("THE PLUGIN HOLDS NOTHING FOR A GAME IT NEVER QUEUED IN",
              ScProdQueueTrackedBuildings(), 0);
        Check("  and nothing at that building in particular",
              ScProdQueueOverflowCount(PqBuilding()), -1);
        Check("  four items counted against the epoch, by name",
              ScProdQueueStat(SC_PRODQ_STAT_STALE_SESSION), 4);
        // THE RESOURCE RULE FOR THIS PATH, and it is the opposite of the building-died
        // one: the minerals were spent in a game that no longer exists.
        Check("NOT ONE MINERAL WAS REFUNDED INTO THE NEW GAME",
              (long long)*PqMinerals(), spentInGameA);
        Check("  and the refund counter did not move",
              ScProdQueueStat(SC_PRODQ_STAT_REFUNDED), 0);
    }

    printf("\n    ...and the same eight presses with NO game start still hold four\n");
    {
        // The positive control. Same fixture, same eight presses, no bump -- so an
        // assertion above that passed because the harness never queued anything is
        // distinguishable from one that passed because the epoch worked.
        PqBegin(16, 1000, 500);
        for (int i = 0; i < 8; ++i) PqTrain(PQ_TYPE_A);
        Check("still holding four", PqOverflow(), 4);
        Check("  one building tracked", ScProdQueueTrackedBuildings(), 1);
        Check("  and nothing was blamed on the epoch",
              ScProdQueueStat(SC_PRODQ_STAT_STALE_SESSION), 0);
    }

    // -----------------------------------------------------------------------
    // #67 item 1: sc_upgrades, whose RecordStillLive is byte-identical to #63's.
    // -----------------------------------------------------------------------
    printf("\n    #67(1) sc_upgrades: a queued research does not promote into another game\n");
    {
        UqBegin(8, 1000, 1000);
        UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_A);   // the engine starts this one
        UqPress(SC_UPGQ_KIND_UPGRADE, UQ_UPG_B);   // the plugin holds this one
        Check("game A: one held", UqQueued(), 1);
        const long long startsInGameA = g_uqStarted;

        ScSessionTestNewGame();

        Check("the plugin holds nothing in the new game", UqQueued(), 0);
        Check("  no building tracked", ScUpgQueueTrackedBuildings(), 0);
        Check("  one item counted against the epoch",
              ScUpgQueueStat(SC_UPGQ_STAT_STALE_SESSION), 1);
        // The consequence, not the bookkeeping: with the record gone there is nothing
        // for a tick in the new game to promote. Without the epoch this tick starts an
        // upgrade the loaded game never asked for.
        UqFinishRunning();
        ScUpgQueueOnTick(UqBuilding());
        Check("A TICK IN THE NEW GAME PROMOTES NOTHING", g_uqStarted, startsInGameA);
    }

    // -----------------------------------------------------------------------
    // #67 item 5: control groups. THE ONE THAT CANNOT BE FIXED BY A PER-UNIT CHECK,
    // and the reason is visible in the fixture: the containment check compares the
    // engine's restored row against the group's records, and a load restores the row
    // NON-EMPTY holding the SAME (pointer, uniqueness) pairs. It passes.
    // -----------------------------------------------------------------------
    printf("\n    #67(5) sc_fanout control groups: BOTH existing defences pass a load\n");
    {
        MakeUnits(64, 1);
        *(BYTE*)FakeRt(SC_VA_ACTIVE_PLAYER_ID) = 1;
        *(BYTE*)FakeRt(SC_VA_PLAYER_ID_512688) = 1;
        *(BYTE*)FakeRt(SC_VA_PLAYER_ID_512678) = 1;

        // --- the control arm: no game start, which is main's behaviour today --------
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        ZeroEngineHotkeys();
        DriveSelection(36);
        Hotkey(SC_HOTKEY_ASSIGN, 5);
        Check("game A: group 5 holds 36", ScFanoutGroupCount(5), 36);
        FakeEngineHotkeyRow(5, kFirstTwelve, 12);
        { DWORD one[1] = { FakeUnit(40) }; ScFanoutOnSelect(1, one); }
        FakeEngineVisible(kFirstTwelve, 12);
        Hotkey(SC_HOTKEY_RECALL, 5);
        Check("WITHOUT a game start the recall restores all 36 -- the defect, reproduced",
              ScFanoutShadowCount(), 36);
        Check("  ResetGroupIfEngineRowEmpty did NOT fire (the row is not empty)",
              ScFanoutGroupStat(SC_FANOUT_GROUP_RESET), 0);
        Check("  and containment did NOT discard it (the pointers all match)",
              ScFanoutGroupStat(SC_FANOUT_GROUP_DISCARD), 0);

        // --- the treatment arm: identical, plus one game start ----------------------
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        ZeroEngineHotkeys();
        DriveSelection(36);
        Hotkey(SC_HOTKEY_ASSIGN, 5);
        Check("game A again: group 5 holds 36", ScFanoutGroupCount(5), 36);
        FakeEngineHotkeyRow(5, kFirstTwelve, 12);

        // THE LOAD. The hotkey row stays exactly as the store left it, because that is
        // what the save file puts back.
        ScSessionTestNewGame();

        {
            const BYTE p = *(BYTE*)FakeRt(SC_VA_ACTIVE_PLAYER_ID);
            const DWORD* row = (DWORD*)FakeRt(SC_VA_SELECTION_HOTKEYS)
                             + (size_t)(p * SC_HOTKEY_GROUPS_PER_PLAYER + 5)
                               * SC_HOTKEY_SLOTS_PER_GROUP;
            Check("the engine's own row for group 5 is STILL non-empty after the load "
                  "-- which is exactly why the empty-row inference cannot see this",
                  row[0] != 0 ? 1 : 0, 1);
        }
        Check("the plugin no longer holds group 5", ScFanoutGroupCount(5), -1);
        Check("  counted against the epoch, not against the empty-row inference",
              ScFanoutGroupStat(SC_FANOUT_GROUP_SESSION) > 0 ? 1 : 0, 1);
        Check("  and the empty-row inference is still at zero, as it must be",
              ScFanoutGroupStat(SC_FANOUT_GROUP_RESET), 0);

        FakeEngineVisible(kFirstTwelve, 12);
        Hotkey(SC_HOTKEY_RECALL, 5);
        Check("THE RECALL GIVES BACK THE ENGINE'S TWELVE, NOT THE OTHER GAME'S 36",
              ScFanoutShadowCount(), 12);
    }

    // -----------------------------------------------------------------------
    // #67 items 2, 3 and 4: the deferred plan, the shadow/accumulator, the version.
    // -----------------------------------------------------------------------
    printf("\n    #67(2,3) sc_fanout: the shadow list and a deferred plan do not cross\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        ResetQueueCounters();
        ZeroEngineHotkeys();
        DriveSelection(36);
        Check("game A: 36 in the shadow list", ScFanoutShadowCount(), 36);
        Check("  12 of them the engine's", ScFanoutVisibleCount(), 12);

        ScSessionTestNewGame();
        Check("the shadow list is empty in the new game", ScFanoutShadowCount(), 0);
        Check("  and so is its visible tail", ScFanoutVisibleCount(), 0);
        Check("  one session drop counted", ScFanoutGroupStat(SC_FANOUT_GROUP_SESSION), 1);

        // The plan. A budget small enough that a 36-unit fan-out cannot finish in one
        // turn is what leaves chunks pending -- the state #67 item 2 is about.
        ScFanoutTestBegin(g_fake, &CaptureEmit, 60);
        ResetQueueCounters();
        DriveSelection(36);
        g_captureLen = 0; g_captureCount = 0;
        Check("game A: the order is fanned out",
              ScFanoutOnCommand(kRightClick, sizeof(kRightClick)) ? 1 : 0, 1);
        Check("  and the budget left chunks pending", ScFanoutPlanActiveForTest(), 1);

        ScSessionTestNewGame();
        Check("THE PLAN IS GONE, so the next command cannot replay the old order",
              ScFanoutPlanActiveForTest(), 0);
        g_captureLen = 0; g_captureCount = 0;
        Check("  and a command in the new game fans nothing out",
              ScFanoutOnCommand(kRightClick, sizeof(kRightClick)) ? 1 : 0, 0);
        Check("  emitting nothing at all", g_captureCount, 0);
    }

    printf("\n    #67(4) the shadow VERSION moves across a game, which a commit counter cannot\n");
    {
        ScFanoutTestBegin(g_fake, &CaptureEmit, 200);
        DriveSelection(36);
        ScShadowInfo snap[64];
        int vis = 0; unsigned verA = 0, verB = 0;
        ScFanoutCopyShadow(snap, 64, &vis, &verA);

        // No commit, no selection change, no click -- only a game start. This is the
        // exact input the counter could not express before, and the reason sc_hudrow
        // kept the previous game's page.
        ScSessionTestNewGame();
        int n = ScFanoutCopyShadow(snap, 64, &vis, &verB);
        Check("the list handed to the HUD row is empty", n, 0);
        Check("AND THE VERSION MOVED, with no selection commit anywhere",
              verB != verA ? 1 : 0, 1);
    }

    // -----------------------------------------------------------------------
    // #67 item 6: circles. The ordering case -- the epoch must be tested BEFORE the
    // CSprite* is dereferenced, because that pointer is a HEAP address.
    // -----------------------------------------------------------------------
    printf("\n    #67(6) sc_circles: a circle from another game is ABANDONED, never detached\n");
    {
        MakeUnits(64, 1);
        MakeSprites(64);
        *(BYTE*)((DWORD)FakeRt(SC_VA_SELECTION_COLOR_TABLE) + 1) = 0x5A;
        ScCirclesTestBegin(g_fake, &FakeAddCircle, &FakeRemoveCircle);
        ResetCircleCounters();

        ScCircleUnit set[3] = { CircleFor(20), CircleFor(21), CircleFor(22) };
        ScCirclesShow(set, 3);
        Check("game A: three circles attached", (long long)g_addCalls, 3);
        Check("  and the module is holding them", ScCirclesCount(), 3);

        ResetCircleCounters();
        ScSessionTestNewGame();

        // THE HEADLINE. RemoveCircle writes through the recorded CSprite*, and after a
        // game end that address is freed heap the allocator may already have handed to
        // this game. So the correct number of detach calls is ZERO, not three.
        ScCirclesHide();
        Check("NOT ONE detach call was made through a stale CSprite*",
              (long long)g_removeCalls, 0);
        Check("  the records were dropped instead", ScCirclesCount(), 0);
        Check("  and counted as abandoned, not as lost",
              (long long)ScCirclesStaleSessionCount(), 3);
        // The positive control for that zero: with no game start the same three DO get
        // detached, so "0 detach calls" is a result and not a harness that never ran.
        ScCirclesTestBegin(g_fake, &FakeAddCircle, &FakeRemoveCircle);
        ResetCircleCounters();
        ScCircleUnit set2[3] = { CircleFor(30), CircleFor(31), CircleFor(32) };
        ScCirclesShow(set2, 3);
        ScCirclesHide();
        Check("without a game start the same three ARE detached",
              (long long)g_removeCalls, 3);
    }

    // -----------------------------------------------------------------------
    // #67 item 4's consumer: the HUD row's page state.
    // -----------------------------------------------------------------------
    printf("\n    #67(4) sc_hudrow: the page and the slot cache do not survive a game\n");
    {
        MakeUnits(64, 1);
        MakeSprites(64);
        for (int i = 0; i < 64; ++i) {
            *(WORD*) (FakeUnit(i) + SC_CUNIT_OFF_UNIT_ID)   = (WORD)(100 + i);
            *(DWORD*)(FakeUnit(i) + SC_CUNIT_OFF_HITPOINTS) = 40 * 256;
        }
        BuildFakePlayerList(64, 1);
        ScFanoutTestBegin(g_fake, NULL, 200);
        BuildFakeDialog();
        ScHudRowTestBegin(g_fake, &FakeShowCtl, &FakeHideCtl, &FakeUpdateCtl,
                          &FakeEngineInteract, &FakeOrigDispatch);
        ScHudRowTestSetBandTiming(0, 0);
        SetHudGlobals(FakeRoot(), FakeUnit(0));

        Drive36Sync();
        ScHudRowOnDispatch();
        Check("game A: 3 pages", ScHudRowPageCount(), 3);
        {
            BYTE rbtn[0x14];
            MakeRButtonEvt(rbtn);
            ScHudRowOnButtonEvent(FakeCtl(3), (DWORD)&rbtn[0]);
            ScHudRowOnDispatch();
        }
        Check("  and the player has flipped to page 2", ScHudRowCurrentPage() + 1, 2);

        ScSessionTestNewGame();
        Check("the new game does not start on the previous game's page",
              ScHudRowCurrentPage() + 1, 1);
        Check("  and there is nothing to page through", ScHudRowPageCount(), 1);
    }
}

// ---------------------------------------------------------------------------
// [23] Code caves (1280 wide). A window's `jmp` out and the cave's `jmp` back
// are two rel32s computed at runtime; a wrong one is a crash inside the game,
// so the arithmetic is EXECUTED here first. The target is a hand-written x86
// function -- mov eax,1 ; add eax,0x58 ; nop ; nop ; ret -- whose 5-byte window
// (a 3-byte imm8 add plus two passengers) is the shape of the fog cell sites,
// and the cave re-encodes it as add eax,0xA8 with an imm32 that no 5-byte
// in-place rewrite could hold.
// ---------------------------------------------------------------------------
static void CodeCaveTests(void) {
    Part("code caves: a window jumps out to a 32-bit re-encoding and back");
    BYTE* fn = (BYTE*)VirtualAlloc(NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!fn) { printf("  FAIL could not allocate the target\n"); ++g_failures; return; }
    static const BYTE kBody[] = {
        0xB8, 0x01, 0x00, 0x00, 0x00,   // mov eax,1
        0x83, 0xC0, 0x58,               // add eax,0x58   <- the window starts here
        0x90, 0x90,                     //   nop ; nop     (passengers: 5 bytes in all)
        0xC3                            // ret            <- where the cave jumps back to
    };
    memcpy(fn, kBody, sizeof(kBody));
    typedef int (*Fn)(void);
    Check("baseline: 1 + 0x58", ((Fn)fn)(), 0x59);

    static const BYTE kCave[] = { 0x05, 0xA8, 0x00, 0x00, 0x00 };    // add eax,0xA8 (imm32)
    Check("apply: 5-byte window at +5, 5-byte cave",
          ScScreenApplyCaveAt(fn + 5, 5, kCave, (int)sizeof(kCave)) ? 1 : 0, 1);
    Check("the window now opens with jmp rel32 (0xE9)", fn[5], 0xE9);
    Check("caved: 1 + 0xA8 through the cave and back", ((Fn)fn)(), 0xA9);

    // A second cave from the same pool must not overlap the first.
    BYTE* fn2 = fn + 64;
    memcpy(fn2, kBody, sizeof(kBody));
    static const BYTE kCave2[] = { 0x05, 0x00, 0x01, 0x00, 0x00 };   // add eax,0x100
    Check("second cave applies", ScScreenApplyCaveAt(fn2 + 5, 5, kCave2, (int)sizeof(kCave2)) ? 1 : 0, 1);
    Check("second cave: 1 + 0x100", ((Fn)fn2)(), 0x101);
    Check("first cave still intact", ((Fn)fn)(), 0xA9);
    Check("refused: a window shorter than the jmp",
          ScScreenApplyCaveAt(fn2 + 5, 4, kCave, (int)sizeof(kCave)) ? 1 : 0, 0);

    // A cave may RETURN from the caved function instead of jumping back -- the
    // console hit-test guard (console.hittest.xguard, sc_screen_patches.h) does
    // exactly that for x >= 640: `cmp ecx,640 / jl +3 / xor eax,eax / ret /
    // <displaced insn>`. EmitCave must copy the body verbatim (a `ret` inside
    // it is not special) and the appended `jmp back` must only be reached on
    // the fall-through path. Drive both paths through ecx.
    BYTE* fn3 = fn + 128;
    memcpy(fn3, kBody, sizeof(kBody));
    static const BYTE kGuard[] = {
        0x81, 0xF9, 0x80, 0x02, 0x00, 0x00,   // cmp ecx,0x280
        0x7C, 0x03,                           // jl +3
        0x33, 0xC0,                           // xor eax,eax
        0xC3,                                 // ret
        0x83, 0xC0, 0x58                      // add eax,0x58 (the displaced window insn)
    };
    Check("guard cave applies (14-byte body with an inner ret)",
          ScScreenApplyCaveAt(fn3 + 5, 5, kGuard, (int)sizeof(kGuard)) ? 1 : 0, 1);
    typedef int (__attribute__((fastcall)) *FnEcx)(int ecx);   // fastcall: first arg in ecx
    Check("ecx=639 falls through the guard: 1 + 0x58 via the cave and back", ((FnEcx)fn3)(639), 0x59);
    Check("ecx=640 returns 0 straight out of the cave", ((FnEcx)fn3)(640), 0);
    Check("ecx=1279 returns 0 too", ((FnEcx)fn3)(1279), 0);
}

int main(void) {
    // Unbuffered: this binary writes executable memory and drives a fake image, so the
    // interesting failure is a fault, and a faulting run must still say WHICH case it
    // was in. With the default buffering the last few hundred lines are lost with the
    // process and the crash looks like it happened at the end of the previous part.
    setvbuf(stdout, NULL, _IONBF, 0);

    // PER PROCESS, not one path for the whole machine. Every worktree used to write
    // %TEMP%\scplugin-hooktest.log, so two workers running run-ci-local.ps1 at the same
    // time fought over one file -- task 030 saw the hooktest gate fail once and pass on a
    // re-run at the SAME commit, which is the worst possible shape for a gate: it makes a
    // real failure indistinguishable from a collision. A caller that wants the log
    // somewhere specific can still set SCPLUGIN_LOG itself; this only fills in a default
    // that cannot collide.
    char tmp[MAX_PATH];
    if (GetEnvironmentVariableA("SCPLUGIN_LOG", tmp, MAX_PATH) == 0) {
        char dir[MAX_PATH];
        GetTempPathA(MAX_PATH, dir);
        wsprintfA(tmp, "%sscplugin-hooktest-%lu.log", dir, GetCurrentProcessId());
        SetEnvironmentVariableA("SCPLUGIN_LOG", tmp);
    }
    ScLogOpen();
    printf("hooktest: log -> %s\n", tmp);

    unsigned slots[4] = { 11, 22, 33, 44 };

    Part("baseline (unhooked)");
    Check("TgtFastcall(5,3) = 5*2+3+7", TgtFastcall(5, 3), 20);
    Check("TgtStdcall(5,3)  = 5+3*3",   TgtStdcall(5, 3), 14);
    CallMixed(2, slots, 100, 1000);
    Check("TgtMixed -> 2+11+100+1000", g_mixedResult, 1113);

    Part("the signature check refuses a wrong prologue");
    {
        ScHook bogus;
        const BYTE wrong[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0x00 };
        bool ok = ScHookInstall(&bogus, "bogus", (void*)&TgtFastcall, (void*)&HkFast,
                                5, wrong, (int)sizeof(wrong));
        Check("install with a mismatched prologue is refused", ok ? 1 : 0, 0);
        Check("nothing was patched: TgtFastcall(5,3)", TgtFastcall(5, 3), 20);
    }

    Part("install the three detours");
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

    Part("detours run, trampolines still compute the original result");
    Check("TgtFastcall(5,3) -> original 20 + 1000", TgtFastcall(5, 3), 1020);
    Check("  detour entered", g_fastCalls, 1);
    Check("TgtFastcall(9,1) -> original 26 + 1000", TgtFastcall(9, 1), 1026);
    Check("TgtStdcall(5,3)  -> original 14 + 2000", TgtStdcall(5, 3), 2014);
    Check("  detour entered", g_stdCalls, 1);

    Part("the register-convention thunk sees EAX/ECX AND the stack args");
    printf("    and the original still runs with every register intact\n");
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

    Part("removal restores the originals exactly");
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

    // THIS ORDER IS THE PART NUMBERING (issue #35). Part() numbers by the order these
    // run, so the list below is the only place a number is decided -- and it is ordered
    // to reproduce the numbers research/ already cites ([8] selection circles, [11]
    // shadow control groups, [12] the exit log, [16] the status strip, ...) rather than
    // to renumber six parts and quietly falsify a dozen citations.
    //
    // ADD NEW PARTS AT THE END. That is the whole mechanism: the next number is
    // whatever the previous one was plus one, nobody claims it, and two branches adding
    // a part each end up with different numbers however they merge.
    //
    // [19] and [20] ARE THAT MECHANISM'S FIRST LIVE TEST. Tasks 033 and 036 merged while
    // this branch was in flight, each hand-numbering a new part: 033 wrote [19] for the
    // queue indicator, 036 wrote [20] for building-group parity -- and 036's ran BEFORE
    // 033's, so on main the parts printed 20 then 19. They did not collide this time; the
    // numbers were simply already lying about the order. Ordered here so the derived
    // numbers match the ones each branch published, and both headers converted to Part(),
    // which is what the numbers now come from.
    FanoutCoreTests();       // [7]
    CircleTests();           // [8]
    OpcodePolicyTests();     // [9]
    HudRowTests();           // [10]
    ControlGroupTests();     // [11]
    ExitLogTests();          // [12]
    BuildingGroupTests();    // [13]
    CardScanTests();         // [14]
    ProdQueueTests();        // [15]
    StatusStripTests();      // [16]
    UpgradeQueueTests();     // [17]
    ProdFanTests();          // [18]
    QueueIndTests();         // [19]  task 033
    BuildingParityTests();   // [20]  task 036
    UpgQueueIndTests();      // [21]  task 037
    SessionEpochTests();     // [22]  task 054
    CodeCaveTests();         // [23]  1280 wide

    printf("\nhooktest: %d failure(s)\n", g_failures);
    ScLogClose();
    return g_failures == 0 ? 0 : 1;
}
