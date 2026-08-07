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

    printf("\n    a unit that dies between attach and detach is left alone\n");
    ResetCircleCounters();
    {
        ScCircleUnit set[2] = { CircleFor(50), CircleFor(51) };
        ScCirclesShow(set, 2);
        // Kill unit 50 the way the engine marks a recycled slot, and give the sprite
        // to somebody else -- which is what makes blind removal dangerous: the flag
        // bit is still set, but it is not our circle any more.
        *(BYTE*)(FakeUnit(50) + SC_CUNIT_OFF_UNIQUENESS) += 1;
        ResetCircleCounters();
        ScCirclesHide();
        Check("only the survivor is detached", (long long)g_removeCalls, 1);
        Check("  it was unit 51's sprite", (long long)g_removedSprites[0], FakeSprite(51));
        *(BYTE*)(FakeUnit(50) + SC_CUNIT_OFF_UNIQUENESS) -= 1;
        *(BYTE*)(FakeSprite(50) + SC_CSPRITE_OFF_FLAGS) = 0;
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
    CircleTests();

    printf("\nhooktest: %d failure(s)\n", g_failures);
    ScLogClose();
    return g_failures == 0 ? 0 : 1;
}
