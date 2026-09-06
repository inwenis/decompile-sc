// sc_circles.cpp -- see sc_circles.h.
//
// ORDERING IS THE WHOLE DESIGN. Two sets of circles exist at once: the engine's (on
// the <=12 units it holds) and ours (on everything the cap threw away). They must
// never overlap, or one of us frees the other's image.
//
//   0x0049AE40 CreateNewUnitSelectionsFromList   <- the client's "replace the whole
//   |                                               selection" funnel, 10 callers
//   |  [OUR PRE-HOOK]  ScCirclesHide()             our circles come off FIRST, while
//   |                                              the engine's old ones are still on
//   |  detach loop over activePlayerSelection      the engine takes its own off
//   |  attach loop over the new list               the engine puts its own on
//   v
//   0x004C0860 CMDACT_Select                     <- sc_fanout's existing hook
//      [OUR HOOK]  ScCirclesShow(overflow units)   our circles go on LAST
//
// Because our detach runs before the engine's attach, a unit can never be in both
// sets: at the moment we let go of a unit the engine has not yet taken it, and at the
// moment we take one the engine has already finished.

#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "sc_addresses.h"
#include "sc_circles.h"
#include "sc_engine.h"
#include "sc_hook.h"
#include "sc_log.h"
#include "sc_session.h"
#include "sc_unit.h"

#define SC_CIRCLES_MAX 256

static void LogCirclePositions(void);

static bool  g_enabled = false;

static ScCircleUnit g_circled[SC_CIRCLES_MAX];
static int          g_circledCount = 0;

static unsigned g_statShown    = 0;   // circles attached
static unsigned g_statHidden   = 0;   // circles detached
static unsigned g_statSkipped  = 0;   // units skipped (engine owns it, or stale)
static unsigned g_statNoImage  = 0;   // the engine's image free list said no
static unsigned g_statLost     = 0;   // recorded unit no longer matched at detach
static unsigned g_statSession  = 0;   // circles abandoned because the game changed

// ---------------------------------------------------------------------------
// THE EPOCH TEST (sc_session.h) -- issue #67 item 6, and THE ONE WHERE THE ORDER OF
// THE CHECKS IS THE FIX RATHER THAN A DETAIL
//
// g_circled[] holds CSprite* HEAP addresses. Every other module in this plugin holds
// CUnit*s, which are seats in a fixed global array: a stale one is always readable and
// only ever wrong. A stale CSprite* is neither -- the sprite was freed when its game
// ended, and the allocator hands the same address out again. So ScCirclesHide's
// `sprite != c->sprite` comparison, which is what stops us freeing an image that is
// not ours, can be satisfied by an unrelated sprite that merely landed on the same
// bytes, and RemoveCircle would then unlink an image out of a live sprite belonging to
// the game the player is actually in.
//
// Hence: this runs BEFORE anything dereferences c->unit or c->sprite, and it drops the
// records rather than detaching them. There is nothing to detach -- the circles went
// with the sprites when the game ended.
static unsigned g_session = 0;

static void CirclesSessionSync(void) {
    const unsigned now = ScSessionEpoch();
    if (g_session == now) return;
    if (g_circledCount > 0) {
        ScLog("CIRCLES session %u -> %u: ABANDONING %d recorded circle(s) without "
              "touching their sprites -- those CSprite* are heap addresses from a game "
              "that has ended, and the memory behind them may already belong to this one",
              g_session, now, g_circledCount);
        g_statSession += (unsigned)g_circledCount;
    }
    g_circledCount = 0;
    g_session = now;
}

// ---------------------------------------------------------------------------
// The two engine primitives
//
// Neither has a calling convention a C declaration can express: both take their
// CSprite* in a register. The call sites they were copied from are quoted above each
// one, so the register setup can be checked against the binary rather than trusted.
// ---------------------------------------------------------------------------

// 0x004D7070. Verbatim from the engine's own call at 0x004E61B4:
//     PUSH 0x231 ; PUSH EAX ; MOV EAX,ESI ; CALL 0x004d7070
// so: EAX = CSprite*, two stdcall arguments, and the callee cleans them (RET 8).
// Returns the new CImage*, or NULL when the image free list is empty.
static DWORD RealAddCircle(DWORD sprite, DWORD colourByte, DWORD baseImageId) {
    DWORD result;
    void* fn = ScRuntimeAddr(SC_VA_SPRITE_ADD_SEL_CIRCLE);
    __asm__ __volatile__(
        "pushl %[img]\n\t"
        "pushl %[col]\n\t"
        "calll *%[fn]\n\t"
        : "=a"(result)
        : "0"(sprite), [col] "r"(colourByte), [img] "r"(baseImageId), [fn] "r"(fn)
        : "ecx", "edx", "cc", "memory");
    return result;
}

// 0x004975D0. Its own first instruction is `MOV AL,byte ptr [ECX + 0xe]` and it ends
// in a bare RET, so: ECX = CSprite*, no stack arguments, nothing to clean. It returns
// the freed image's colour byte in AL, which we ignore.
static BYTE RealRemoveCircle(DWORD sprite) {
    DWORD result;
    DWORD spriteInOut = sprite;
    void* fn = ScRuntimeAddr(SC_VA_SPRITE_REMOVE_SEL_CIRCLE);
    __asm__ __volatile__(
        "calll *%[fn]\n\t"
        : "=a"(result), "=c"(spriteInOut)
        : "1"(spriteInOut), [fn] "r"(fn)
        : "edx", "cc", "memory");
    return (BYTE)(result & 0xFF);
}

static ScAddCircleFn    g_add    = NULL;
static ScRemoveCircleFn g_remove = NULL;

static DWORD AddCircle(DWORD sprite, DWORD colour, DWORD baseId) {
    return g_add ? g_add(sprite, colour, baseId) : RealAddCircle(sprite, colour, baseId);
}
static BYTE RemoveCircle(DWORD sprite) {
    return g_remove ? g_remove(sprite) : RealRemoveCircle(sprite);
}

// ---------------------------------------------------------------------------
// Reading game memory without trusting it
// ---------------------------------------------------------------------------

// A CSprite pointer comes out of a CUnit that may have died since we recorded it, so
// it is never dereferenced until the whole struct is known to sit inside one
// committed, readable, non-guard region. This is the same defence scplugin.cpp's
// observer uses for its reads, kept local so this module has no dependency on it.

// CSprite is 0x24 bytes (prev, next, ids, flags, size, position, three image
// pointers) -- research/selection-circles.md 2.1. Requiring the whole struct rather
// than just the flags byte means a pointer landing on the last bytes of a region
// fails here instead of faulting inside the engine.
#define SC_CSPRITE_SIZE 0x24u

static bool SpriteOf(DWORD unit, DWORD* outSprite) {
    if (!ScUnitPtrValid(unit)) return false;
    if (!ScReadable(unit + SC_CUNIT_OFF_SPRITE, 4)) return false;
    DWORD sprite = ScUnitSprite(unit);
    if (!ScReadable(sprite, SC_CSPRITE_SIZE)) return false;
    *outSprite = sprite;
    return true;
}

static BYTE* SpriteFlags(DWORD sprite) {
    return (BYTE*)(sprite + SC_CSPRITE_OFF_FLAGS);
}

// ---------------------------------------------------------------------------
// Attach / detach
// ---------------------------------------------------------------------------

void ScCirclesHide(void) {
    // FIRST -- before the count check and before any pointer in g_circled is looked at.
    // See CirclesSessionSync: a record from a previous game must be abandoned, never
    // detached, because detaching means writing through a freed CSprite*.
    CirclesSessionSync();
    if (g_circledCount == 0) return;

    int removed = 0;
    for (int i = 0; i < g_circledCount; ++i) {
        const ScCircleUnit* c = &g_circled[i];
        DWORD sprite = 0;

        // Four things must still be true, and each rules out a different way this
        // record can have gone bad since ScCirclesShow recorded it:
        //   1. the unit still exists and is the SAME unit (uniqueness, CUnit+0xA5) --
        //      the engine's own staleness test for a stored unit;
        //   2. it still points at the same CSprite -- a unit that died and came back
        //      gets a different one, and the old one is on the sprite free list;
        //   3. the circle flag is still set -- if it is not, the engine has already
        //      taken the circle off and there is nothing of ours left;
        //   4. the engine has NOT since marked the sprite selected -- if it had, the
        //      circle now belongs to the engine and removing it would leave a
        //      genuinely selected unit with a health bar and no circle.
        // Ordering makes 4 unreachable in practice (we detach before the engine
        // attaches); it is checked anyway because "unreachable" and "never happens"
        // are different claims, and the counter says which.
        if (!SpriteOf(c->unit, &sprite) || sprite != c->sprite ||
            ScUnitUniqueness(c->unit) != c->uniqueness) {
            ++g_statLost;
            continue;
        }
        BYTE flags = *SpriteFlags(sprite);
        if ((flags & SC_SPRITE_FLAG_SEL_CIRCLE) == 0) { ++g_statLost; continue; }
        if ((flags & SC_SPRITE_FLAG_SELECTED) != 0) {
            ScLog("CIRCLES: unit 0x%08X became engine-selected while we held its "
                  "circle -- leaving it alone", (unsigned)c->unit);
            ++g_statLost;
            continue;
        }

        RemoveCircle(sprite);
        ++removed;
        ++g_statHidden;
    }

    ScLog("CIRCLES hide: %d/%d removed", removed, g_circledCount);
    g_circledCount = 0;
}

void ScCirclesShow(const ScCircleUnit* units, int n) {
    if (!g_enabled) return;
    CirclesSessionSync();
    ScCirclesHide();
    if (!units || n <= 0) return;

    int shown = 0;
    for (int i = 0; i < n && g_circledCount < SC_CIRCLES_MAX; ++i) {
        DWORD sprite = 0;
        if (!SpriteOf(units[i].unit, &sprite)) { ++g_statSkipped; continue; }
        if (ScUnitUniqueness(units[i].unit) != units[i].uniqueness) {
            ++g_statSkipped;
            continue;
        }

        BYTE flags = *SpriteFlags(sprite);
        // Already the engine's: it holds this unit in its 12, or something else has
        // put a circle on this sprite. Either way the image is not ours to own, and
        // adopting it would mean freeing someone else's image later.
        if (flags & (SC_SPRITE_FLAG_SELECTED | SC_SPRITE_FLAG_SEL_CIRCLE)) {
            ++g_statSkipped;
            continue;
        }

        // The colour byte the engine would have used: BYTE[0x00581D6A + player],
        // read exactly as 0x004E61A6 reads it.
        BYTE colour = *(BYTE*)(ScRuntimeVa(SC_VA_SELECTION_COLOR_TABLE) + units[i].player);

        DWORD img = AddCircle(sprite, colour, SC_SELECTION_CIRCLE_IMAGE_BASE);
        if (!img) {
            // The engine's image free list is empty. Not an error we can do anything
            // about, and not a reason to stop: later units may still fit.
            ++g_statNoImage;
            continue;
        }
        *SpriteFlags(sprite) = (BYTE)(flags | SC_SPRITE_FLAG_SEL_CIRCLE);

        ScCircleUnit rec = units[i];
        rec.sprite = sprite;
        g_circled[g_circledCount++] = rec;
        ++shown;
        ++g_statShown;
    }

    ScLog("CIRCLES show: %d/%d units circled (noImage=%u skipped=%u)",
          shown, n, g_statNoImage, g_statSkipped);
    LogCirclePositions();
}

// Where the circled units are ON SCREEN, in client pixels.
//
// This exists for one reason: an automated test cannot aim a click at "one of the units
// the plugin circled" unless something tells it where they are. Without it the only
// >12 shift-click a test can perform lands on whichever unit happens to be there, and
// has to accept either outcome -- which is a much weaker assertion than the one this
// design deserves (tools/plugin/test-selection-circles.ps1, step 7).
//
// client = mapPixel - viewportOrigin, with the origin read exactly where the click
// handler at 0x0046FB40 reads it. Purely diagnostic: nothing in the feature depends on
// these two globals, and a wrong value here can only mis-aim a test, never mis-draw a
// circle.
static void LogCirclePositions(void) {
    if (g_circledCount <= 0) return;

    const int left = (int)*(WORD*)ScRuntimeAddr(SC_VA_SCREEN_LEFT);
    const int top  = (int)*(WORD*)ScRuntimeAddr(SC_VA_SCREEN_TOP);
    // The client's size is the engine's own screen bitmap descriptor (640x480
    // stock, the widescreen table's size once it is live) -- read, not assumed,
    // so a wider game does not drop every unit past x=639 as "off-screen".
    int scrW = SC_SCREEN_W, scrH = SC_SCREEN_H;
    if (ScReadable(ScRuntimeVa(SC_VA_SCREEN_BITMAP), 4)) {
        const int w = (int)*(WORD*)ScRuntimeAddr(SC_VA_SCREEN_BITMAP + SC_BITMAP_OFF_WIDTH);
        const int h = (int)*(WORD*)ScRuntimeAddr(SC_VA_SCREEN_BITMAP + SC_BITMAP_OFF_HEIGHT);
        if (w > 0 && h > 0) { scrW = w; scrH = h; }
    }

    char buf[1024];
    int used = 0;
    int listed = 0;
    for (int i = 0; i < g_circledCount; ++i) {
        const DWORD s = g_circled[i].sprite;
        if (!ScReadable(s, SC_CSPRITE_SIZE)) continue;
        const int x = (int)*(WORD*)(s + SC_CSPRITE_OFF_POS_X) - left;
        const int y = (int)*(WORD*)(s + SC_CSPRITE_OFF_POS_Y) - top;
        // Off-screen units are useless to a test and would only be noise. scrW and
        // scrH are the first coordinates OUTSIDE the client -- an inclusive bound
        // here would hand a test a point one pixel off the window.
        if (x < 0 || y < 0 || x >= scrW || y >= scrH) continue;
        const int room = (int)sizeof(buf) - used;
        if (room < 24) { break; }
        used += _snprintf(buf + used, (size_t)room, "%s%d,%d", listed ? " " : "", x, y);
        ++listed;
    }
    if (listed == 0) return;
    buf[sizeof(buf) - 1] = '\0';
    ScLog("CIRCLES pos: %d on screen of %d: %s", listed, g_circledCount, buf);
}

int ScCirclesCount(void) { CirclesSessionSync(); return g_circledCount; }
unsigned ScCirclesStaleSessionCount(void) { CirclesSessionSync(); return g_statSession; }

// ---------------------------------------------------------------------------
// The hook: CreateNewUnitSelectionsFromList (0x0049AE40)
//
// EAX = CUnit**, one stdcall argument (count), RET 4. No C calling convention
// describes that, and the detour must not disturb either -- so it is an explicit
// thunk that saves everything, calls a normal C function that takes no arguments at
// all, restores, and jumps to the trampoline. The stack argument is never touched.
// ---------------------------------------------------------------------------

extern "C" void ScCirclesOnSelectionChange(void);
extern "C" void ScCirclesSelChangeThunk(void);
extern "C" void* g_selChangeTrampoline;
void* g_selChangeTrampoline = NULL;

asm(
    ".text\n"
    ".globl _ScCirclesSelChangeThunk\n"
"_ScCirclesSelChangeThunk:\n"
    "  pushal\n"
    "  pushfl\n"
    "  call _ScCirclesOnSelectionChange\n"
    "  popfl\n"
    "  popal\n"
    "  jmp *_g_selChangeTrampoline\n"
);

// force_align_arg_pointer for the same reason sc_fanout.cpp puts it on every entry
// point the game calls: GCC at -O2 assumes a 16-byte-aligned incoming stack and will
// emit aligned SSE spills on that assumption, while StarCraft is a VC6-class build
// that guarantees 4.
extern "C" void __attribute__((force_align_arg_pointer))
ScCirclesOnSelectionChange(void) {
    ScCirclesHide();
}

static ScHook g_hkSelChange;

// Verified prologue -- ScHookInstall refuses to patch if memory disagrees. Bytes and
// the 5-byte/4-instruction patch window come from HookProbe against this binary
// (work/scratch/selhooks/CreateNewUnitSelectionsFromList.FUN_0049ae40.asm):
//     0x0049AE40  55        PUSH EBP
//     0x0049AE41  8BEC      MOV EBP,ESP
//     0x0049AE43  53        PUSH EBX
//     0x0049AE44  56        PUSH ESI
// none of which is PC-relative, so all four relocate into the trampoline unchanged.
static const BYTE kPrologueSelChange[] = { 0x55, 0x8B, 0xEC, 0x53, 0x56 };

int ScCirclesInstall(void) {
    if (!g_enabled) return 0;
    if (!ScHookInstall(&g_hkSelChange, "CreateNewUnitSelectionsFromList",
                       ScRuntimeAddr(SC_VA_CREATE_NEW_UNIT_SELECTIONS),
                       (void*)&ScCirclesSelChangeThunk, 5,
                       kPrologueSelChange, (int)sizeof(kPrologueSelChange))) {
        return 0;
    }
    g_selChangeTrampoline = g_hkSelChange.trampoline;
    return 1;
}

void ScCirclesRemove(void) {
    ScHookRemove(&g_hkSelChange);
}

// ---------------------------------------------------------------------------
// Mode + stats
// ---------------------------------------------------------------------------

void ScCirclesInit(BYTE* moduleBase, bool enabled) {
    ScEngineSetModuleBase(moduleBase);
    g_enabled = enabled;
    g_add     = NULL;
    g_remove  = NULL;
    g_circledCount = 0;
    g_session = ScSessionEpoch();
}

bool ScCirclesEnabled(void) { return g_enabled; }

void ScCirclesTestBegin(BYTE* fakeModuleBase, ScAddCircleFn add, ScRemoveCircleFn remove) {
    ScEngineSetModuleBase(fakeModuleBase);
    g_enabled = true;
    g_add     = add;
    g_remove  = remove;
    g_circledCount = 0;
    g_session = ScSessionEpoch();
    g_statShown = g_statHidden = g_statSkipped = g_statNoImage = g_statLost = 0;
    g_statSession = 0;
}

void ScCirclesLogStats(void) {
    if (!g_enabled) return;
    ScLog("CIRCLES stats: session=%u shown=%u hidden=%u held=%d skipped=%u noImage=%u "
          "lost=%u staleSession=%u",
          g_session, g_statShown, g_statHidden, g_circledCount, g_statSkipped,
          g_statNoImage, g_statLost, g_statSession);
}
