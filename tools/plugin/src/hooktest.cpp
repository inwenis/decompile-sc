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
#include "sc_prodqueue.h"

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
          ScFanoutDroppedFor(SC_FANOUT_RECYCLED), 3);
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
              ScFanoutDroppedFor(SC_FANOUT_DEAD), 1);
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
              ScFanoutDroppedFor(SC_FANOUT_REMOVED), 1);
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
        Check("dropped as FOREIGN", ScFanoutDroppedFor(SC_FANOUT_FOREIGN), 1);
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
        Check("dropped as NOSPRITE", ScFanoutDroppedFor(SC_FANOUT_NOSPRITE), 1);
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
        Check("all 12 were charged to hp0", ScFanoutDroppedFor(SC_FANOUT_DEAD), 12);
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
    printf("\n[11] shadow control groups: Ctrl+N over 12, and N brings them back\n");

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
        Check("  one assign counted", ScFanoutGroupStat(SC_GROUPSTAT_ASSIGN), 1);

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
        Check("  counted as a >12 recall", ScFanoutGroupStat(SC_GROUPSTAT_WIDE), 1);
        Check("  nothing was discarded", ScFanoutGroupStat(SC_GROUPSTAT_DISCARD), 0);

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
        Check("  one discard counted", ScFanoutGroupStat(SC_GROUPSTAT_DISCARD), 1);
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
        Check("  no reset counted", ScFanoutGroupStat(SC_GROUPSTAT_RESET), 0);

        // Now a new game: 0x004EEC30 zeroes the whole array.
        ZeroEngineHotkeys();
        { DWORD fresh[1] = { FakeUnit(50) }; ScFanoutOnSelect(1, fresh); }
        Hotkey(SC_HOTKEY_ADD, 5);
        Check("the stale group was dropped, so the add behaves as an assign",
              ScFanoutGroupCount(5), 1);
        Check("  a reset was counted", ScFanoutGroupStat(SC_GROUPSTAT_RESET) > 0 ? 1 : 0, 1);
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
        Check("  and a reset was counted", ScFanoutGroupStat(SC_GROUPSTAT_RESET) > 0 ? 1 : 0, 1);
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
              ScFanoutGroupStat(SC_GROUPSTAT_DISCARD), 1);
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
        Check("  one add counted", ScFanoutGroupStat(SC_GROUPSTAT_ADD), 1);
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
        Check("  and no group was touched", ScFanoutGroupStat(SC_GROUPSTAT_RECALL), 0);

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

// The candidate list SortAllUnits is handed: CUnit pointers, NULL-terminated.
static void MakeCandidates(DWORD* buf, const int* idx, int n) {
    for (int i = 0; i < n; ++i) buf[i] = FakeUnit(idx[i]);
    buf[n] = 0;
}

static void BuildingGroupTests(void) {
    printf("\n[13] same-type building groups: one box, N buildings, N rallies\n");

    // Its own fake image, like every other part: each one releases the previous one's.
    g_fake = (BYTE*)VirtualAlloc(NULL, FAKE_IMAGE_BYTES, MEM_COMMIT | MEM_RESERVE,
                                 PAGE_READWRITE);
    if (!g_fake) { printf("  FAIL could not allocate the fake image\n"); ++g_failures; return; }

    MakeUnits(64, 1);
    ResetQueueCounters();
    ScFanoutTestBegin(g_fake, &CaptureEmit, 400);
    ScFanoutTestSetMovable(&FakeMovable);

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
        const int before = ScFanoutGroupRefusedFor(SC_FANOUT_DEAD);

        DWORD cand[8];
        const int all[4] = { 0, 1, 2, 3 };
        MakeCandidates(cand, all, 4);
        DWORD out[SC_SELECTION_SLOTS] = { 0 };
        out[0] = FakeUnit(3);
        unsigned n = ScFanoutGrowBuildingGroup(cand, out, 0, 1);
        Check("a destroyed building never enters the selection", (int)n, 3);
        Check("  and it was refused for being DEAD, not merely absent",
              ScFanoutGroupRefusedFor(SC_FANOUT_DEAD) - before, 1);
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

        Check("a CLICK (clicked != 0) is untouched",
              (int)ScFanoutGrowBuildingGroup(cand, out, FakeUnit(3), 1), 1);
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
// [11] The production-queue core (task 025), driven with no game and no hooks.
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
    printf("\n[11] the production-queue core: >5 queued, no game, no hooks\n");

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
    Check("the ENGINE paid for all five",  (long long)*PqMinerals(), 1000 - 5 * 50);
    Check("and the plugin spent NOTHING",  ScProdQueueStat(SC_PRODQ_STAT_MINERALS_SPENT), 0);
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

    printf("\n    a cancel that names a SLOT is never ours -- the engine refunds it\n");
    PqBegin(16, 1000, 500);
    for (int i = 0; i < 5; ++i) PqTrain(PQ_TYPE_A);
    for (unsigned slot = 0; slot < SC_BUILD_QUEUE_SLOTS; ++slot) {
        Check("slot cancel passes through", ScProdQueueOnCancel(PqBuilding(), slot) ? 1 : 0, 0);
    }
    Check("0xFF (the no-op form) passes through",
          ScProdQueueOnCancel(PqBuilding(), SC_CANCEL_TRAIN_NONE) ? 1 : 0, 0);
    Check("what the plugin holds is untouched", ScProdQueueOverflowCount(PqBuilding()), 1);
    Check("money untouched",    (long long)*PqMinerals(), 1000 - 5 * 50);

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
    Check("the plugin still spent nothing",
          ScProdQueueStat(SC_PRODQ_STAT_MINERALS_SPENT), 0);

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
        Check("the plugin never spent a mineral of its own",
              ScProdQueueStat(SC_PRODQ_STAT_MINERALS_SPENT), 0);
        Check("total spend is sixteen costs, not seventeen and not twenty-seven",
              (long long)(start - *PqMinerals()), 16 * 50);
    }

    ScProdQueueTestBegin(NULL, 0);   // leave the core inert for the parts after this
}

static void ExitLogTests(void) {
    printf("\n[12] the exit log path writes even when the lock is dead-owned\n");

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

int main(void) {
    // Unbuffered: this binary writes executable memory and drives a fake image, so the
    // interesting failure is a fault, and a faulting run must still say WHICH case it
    // was in. With the default buffering the last few hundred lines are lost with the
    // process and the crash looks like it happened at the end of the previous part.
    setvbuf(stdout, NULL, _IONBF, 0);

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
    ControlGroupTests();
    ProdQueueTests();
    BuildingGroupTests();
    ExitLogTests();

    printf("\nhooktest: %d failure(s)\n", g_failures);
    ScLogClose();
    return g_failures == 0 ? 0 : 1;
}
