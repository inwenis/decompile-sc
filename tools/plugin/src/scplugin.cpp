// scplugin.cpp -- StarCraft 1.16.1 plugin DLL.
//
// WHAT THIS DOES
//   Loaded into a running StarCraft.exe by scinject.exe. On attach it records the
//   process id, the module base StarCraft.exe actually loaded at, and the relocation
//   delta against the PE's preferred base. It then polls the selection globals
//   mapped statically in research/binary-selection-map.md and appends a line to a
//   log file whenever the observed state changes (task 008, rung 1).
//
//   Depending on %SCPLUGIN_MODE% it additionally installs the fan-out hooks
//   (task 011, sc_fanout.cpp), which is the only part of this plugin that writes to
//   game memory:
//
//     observe   (DEFAULT)  read-only. No hooks, no writes, byte-for-byte the
//                          task-008 observer. THIS IS THE OFF SWITCH.
//     hooktest             one hook (queueCommand), logging only, no behaviour change
//     shadow               + capture the pre-cap selection and log it, still no
//                          behaviour change
//     fanout               + fan orders out over the whole captured selection
//
//   Unset, misspelled, or unrecognised -> observe. The plugin is passive unless
//   something explicitly asks for more.
//
// WHAT THIS NEVER DOES
//   It never patches StarCraft.exe on disk. Every modification is in this process's
//   memory, is reversible, and is undone on unload. The game directory is not
//   written to at all.
//
// Log destination: %SCPLUGIN_LOG% if set, else C:\sc-work\logs\sc-plugin.log.
// Both are outside the repo; C:/sc-work/ is gitignored -- no captured game data is
// ever committed (AGENTS.md hard rule 1).

#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "sc_addresses.h"
#include "sc_card.h"
#include "sc_fanout.h"
#include "sc_hook.h"
#include "sc_log.h"
#include "sc_prodqueue.h"

static volatile LONG g_stop = 0;

// ---------------------------------------------------------------------------
// Read-only memory access
// ---------------------------------------------------------------------------

// Copies n bytes out of the target address if, and only if, the whole range sits
// inside one committed, readable region. Returns false instead of faulting on a bad
// address, so a wrong static offset produces a log line saying "unreadable" rather
// than a crashed game.
static bool SafeRead(const void* addr, void* out, size_t n) {
    MEMORY_BASIC_INFORMATION mbi;
    if (VirtualQuery(addr, &mbi, sizeof(mbi)) != sizeof(mbi)) return false;
    if (mbi.State != MEM_COMMIT) return false;
    if (mbi.Protect & PAGE_GUARD) return false;

    const DWORD readable = PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY |
                           PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE |
                           PAGE_EXECUTE_WRITECOPY;
    if ((mbi.Protect & readable) == 0) return false;

    const BYTE* start  = (const BYTE*)addr;
    const BYTE* regEnd = (const BYTE*)mbi.BaseAddress + mbi.RegionSize;
    if (start < (const BYTE*)mbi.BaseAddress) return false;
    if (start + n > regEnd) return false;

    memcpy(out, addr, n);
    return true;
}

// ---------------------------------------------------------------------------
// Selection snapshot
// ---------------------------------------------------------------------------

struct Snapshot {
    BYTE  count;                              // clientSelectionCount (u8)
    BYTE  iterator;                           // selectionIterator (u8)
    DWORD playerId;                           // 0x0051267C
    DWORD playerId688;                        // 0x00512688
    DWORD playerId678;                        // 0x00512678
    DWORD group[SC_SELECTION_SLOTS];          // clientSelectionGroup
    DWORD group2[SC_SELECTION_SLOTS];         // clientSelectionGroup2
    DWORD active[SC_SELECTION_SLOTS];         // activePlayerSelection
    DWORD playerRow[SC_SELECTION_SLOTS];      // playersSelections[playerId]
    BYTE  ok;                                 // bitmask of which reads succeeded
};

enum {
    OK_COUNT = 1 << 0, OK_GROUP = 1 << 1, OK_GROUP2 = 1 << 2,
    OK_ACTIVE = 1 << 3, OK_ROW = 1 << 4, OK_IDS = 1 << 5
};

static BYTE* g_base = NULL;   // actual load address of StarCraft.exe

static void* Rt(DWORD staticVa) {
    return (void*)(g_base + (staticVa - SC_PREFERRED_IMAGE_BASE));
}

static int NonNull(const DWORD* arr) {
    int n = 0;
    for (int i = 0; i < SC_SELECTION_SLOTS; ++i) if (arr[i]) ++n;
    return n;
}

static void FormatSlots(const DWORD* arr, char* out, size_t outLen) {
    size_t used = 0;
    out[0] = '\0';
    for (int i = 0; i < SC_SELECTION_SLOTS; ++i) {
        if (!arr[i]) continue;
        char one[32];
        int k = _snprintf(one, sizeof(one) - 1, "%s[%d]=0x%08lX",
                          used ? " " : "", i, (unsigned long)arr[i]);
        if (k < 0) break;
        one[sizeof(one) - 1] = '\0';
        if (used + (size_t)k + 1 >= outLen) break;
        memcpy(out + used, one, (size_t)k + 1);
        used += (size_t)k;
    }
    if (used == 0) lstrcpynA(out, "(none)", (int)outLen);
}

static void TakeSnapshot(Snapshot* s) {
    memset(s, 0, sizeof(*s));

    if (SafeRead(Rt(SC_VA_CLIENT_SELECTION_COUNT), &s->count, 1)) s->ok |= OK_COUNT;
    SafeRead(Rt(SC_VA_SELECTION_ITERATOR), &s->iterator, 1);

    if (SafeRead(Rt(SC_VA_ACTIVE_PLAYER_ID), &s->playerId, 4) &&
        SafeRead(Rt(SC_VA_PLAYER_ID_512688), &s->playerId688, 4) &&
        SafeRead(Rt(SC_VA_PLAYER_ID_512678), &s->playerId678, 4)) {
        s->ok |= OK_IDS;
    }

    if (SafeRead(Rt(SC_VA_CLIENT_SELECTION_GROUP), s->group, sizeof(s->group)))
        s->ok |= OK_GROUP;
    if (SafeRead(Rt(SC_VA_CLIENT_SELECTION_GROUP2), s->group2, sizeof(s->group2)))
        s->ok |= OK_GROUP2;
    if (SafeRead(Rt(SC_VA_ACTIVE_PLAYER_SELECTION), s->active, sizeof(s->active)))
        s->ok |= OK_ACTIVE;

    // playersSelections[player] -- clamp the index, the id global is exactly the
    // kind of thing this task exists to check rather than trust.
    DWORD p = (s->ok & OK_IDS) ? (s->playerId & 0xFF) : 0;
    if (p < SC_MAX_PLAYERS) {
        DWORD rowVa = SC_VA_PLAYERS_SELECTIONS + p * SC_SELECTION_SLOTS * 4;
        if (SafeRead(Rt(rowVa), s->playerRow, sizeof(s->playerRow))) s->ok |= OK_ROW;
    }
}

static void LogSnapshot(const Snapshot* s) {
    char gbuf[512], abuf[512], rbuf[512], g2buf[512];
    FormatSlots(s->group,     gbuf,  sizeof(gbuf));
    FormatSlots(s->active,    abuf,  sizeof(abuf));
    FormatSlots(s->playerRow, rbuf,  sizeof(rbuf));
    FormatSlots(s->group2,    g2buf, sizeof(g2buf));

    ScLog("SEL count=%u nonNullGroup=%d iter=%u player=%u/%u/%u ok=0x%02X",
          (unsigned)s->count, NonNull(s->group), (unsigned)s->iterator,
          (unsigned)s->playerId, (unsigned)s->playerId688,
          (unsigned)s->playerId678, (unsigned)s->ok);
    ScLog("    clientSelectionGroup   %s", gbuf);
    ScLog("    activePlayerSelection  %s", abuf);
    ScLog("    playersSelections[%u]   %s", (unsigned)(s->playerId & 0xFF), rbuf);
    ScLog("    clientSelectionGroup2  %s", g2buf);
}

// ---------------------------------------------------------------------------
// World scan (task 022) -- READ-ONLY, and deliberately INDEPENDENT of the hooks
//
// The fan-out's UNITSTATE line walks the SHADOW list, so it exists only in a mode
// that installs hooks. Task 022 needs an oracle that also works in `-Mode observe`
// -- the fully stock control run -- because the question it answers is "does the
// game behave differently with our plugin in it?", and an oracle that only exists
// on one side of that comparison cannot answer it.
//
// So this walks the ENGINE's own per-player unit lists (playerUnitList,
// SC_VA_PLAYER_UNIT_LIST, threaded on CUnit+0x6C -- sc_addresses.h) and reports one
// line per unit. Every read goes through SafeRead, exactly like the selection
// snapshot: a wrong offset produces a missing field, never a fault inside the game.
// Nothing here writes, hooks, or calls into the game -- it is the task-008 observer
// pointed at a different global.
//
// Off by default (%SCPLUGIN_WORLDSCAN%, launcher flag -WorldScan 1): the existing
// suites parse this log, and a fixture with 36 units would otherwise add 36 lines
// per marker to every one of their runs.
// ---------------------------------------------------------------------------

static bool g_worldScan = false;

// Per player, so one runaway list cannot bury the log. A fixture big enough to hit
// this is a fixture whose per-unit detail was never going to be readable anyway.
#define SC_WORLDSCAN_MAX_LINES 64

static bool ReadU8(DWORD addr, unsigned* out) {
    BYTE v = 0;
    if (!SafeRead((const void*)addr, &v, 1)) return false;
    *out = v;
    return true;
}

static bool ReadU16(DWORD addr, unsigned* out) {
    WORD v = 0;
    if (!SafeRead((const void*)addr, &v, 2)) return false;
    *out = v;
    return true;
}

static bool ReadU32(DWORD addr, DWORD* out) {
    DWORD v = 0;
    if (!SafeRead((const void*)addr, &v, 4)) return false;
    *out = v;
    return true;
}

// The same bounds/stride test the fan-out applies before it follows a unit pointer
// (sc_fanout.cpp UnitPtrValid): inside the unit array, on a CUnit stride, within the
// index range the wire tag can encode. A link that fails it is a torn read of a list
// the game thread is editing, not a unit -- following it is what turns a benign race
// into a fault.
static bool WorldUnitPtrValid(DWORD ptr) {
    if (!ptr) return false;
    DWORD arrayBase = (DWORD)(DWORD_PTR)Rt(SC_VA_UNIT_ARRAY_BASE);
    if (ptr < arrayBase) return false;
    DWORD off = ptr - arrayBase;
    if (off % SC_CUNIT_SIZE != 0) return false;
    return (off / SC_CUNIT_SIZE + 1) <= SC_MAX_UNIT_INDEX;
}

// Counts one player's list without logging. Used for the second pass -- see ScanWorld.
static int CountPlayerUnits(int p, bool* ok) {
    DWORD head = 0;
    *ok = false;
    if (!ReadU32((DWORD)(DWORD_PTR)Rt(SC_VA_PLAYER_UNIT_LIST) + (DWORD)p * 4, &head))
        return 0;
    int n = 0;
    for (DWORD u = head; u && n < SC_MAX_UNITS_WALK; ) {
        if (!WorldUnitPtrValid(u)) return n;
        DWORD next = 0;
        if (!ReadU32(u + SC_CUNIT_OFF_LIST_NEXT, &next)) return n;
        u = next;
        ++n;
    }
    *ok = true;
    return n;
}

// ---------------------------------------------------------------------------
// Screen/viewport scan (task 032) -- READ-ONLY
//
// Why it exists: research/renderer-viewport.md is a static map, and a static map of a
// subsystem nobody had touched before is exactly the kind of claim this project has been
// burned by. AGENTS.md's standing rule is to READ THE ENGINE'S OWN MEMORY rather than reason
// about it, so every number that document asserts about the live layout -- the screen
// Bitmap's width/height/pointer, each graphic layer's rectangle and draw callback, the
// scroll maxima and the tile-granular origin -- is printed here straight out of the running
// process and quoted back into the document beside the disassembly it was predicted from.
//
// It installs NO hook, calls nothing in the game and writes nothing, so it runs in
// -Mode observe. Off by default (%SCPLUGIN_SCREENSCAN%, launcher flag -ScreenScan 1): it
// adds ten lines per marker and the existing suites parse this same log.
//
// The layer draw callbacks are printed as STATIC VAs (runtime minus the relocation delta)
// so they can be compared directly against the addresses in sc_addresses.h and the Ghidra
// listing, which is the whole point of reading them.
// ---------------------------------------------------------------------------

static bool g_screenScan = false;

static void ScanScreen(const char* tag) {
    if (!g_screenScan) return;
    const char* t = tag ? tag : "-";
    const DWORD delta = (DWORD)(DWORD_PTR)g_base - SC_PREFERRED_IMAGE_BASE;

    // The screen Bitmap. `data` is the 640*480 SMemAlloc from 0x004DB060; a non-zero value
    // here is the evidence that the buffer exists and that the descriptor is the live one.
    {
        DWORD b = (DWORD)(DWORD_PTR)Rt(SC_VA_SCREEN_BITMAP);
        unsigned w = 0xFFFF, h = 0xFFFF;
        DWORD data = 0;
        bool okW = ReadU16(b + SC_BITMAP_OFF_WIDTH, &w);
        bool okH = ReadU16(b + SC_BITMAP_OFF_HEIGHT, &h);
        bool okD = ReadU32(b + SC_BITMAP_OFF_DATA, &data);
        ScLog("SCREEN [%s] bitmap@0x%08X w=%s%u h=%s%u data=%s0x%08X bytes=%u",
              t, (unsigned)SC_VA_SCREEN_BITMAP,
              okW ? "" : "?", w, okH ? "" : "?", h, okD ? "" : "?", (unsigned)data,
              (okW && okH) ? w * h : 0);
    }

    // The eight graphic layers. Printed in DRAW ORDER -- 7 first, 0 last -- because that is
    // the order 0x0041E280 walks them in, and "layer 0 is the cursor" is only meaningful
    // next to the direction of the walk.
    for (int i = SC_GRAPHIC_LAYERS - 1; i >= 0; --i) {
        DWORD l = (DWORD)(DWORD_PTR)Rt(SC_VA_GRAPHIC_LAYERS) + (DWORD)i * SC_LAYER_STRIDE;
        unsigned used = 0xFF, flags = 0xFF;
        unsigned left = 0, top = 0, width = 0, height = 0;
        DWORD param = 0, draw = 0;
        ReadU8(l + SC_LAYER_OFF_USED, &used);
        ReadU8(l + SC_LAYER_OFF_FLAGS, &flags);
        ReadU16(l + SC_LAYER_OFF_LEFT, &left);
        ReadU16(l + SC_LAYER_OFF_TOP, &top);
        ReadU16(l + SC_LAYER_OFF_WIDTH, &width);
        ReadU16(l + SC_LAYER_OFF_HEIGHT, &height);
        ReadU32(l + SC_LAYER_OFF_PARAM, &param);
        ReadU32(l + SC_LAYER_OFF_DRAW, &draw);
        ScLog("SCREEN [%s] layer=%d used=%u flags=0x%02X rect=(%d,%d %ux%u) param=0x%08X "
              "draw=0x%08X drawStatic=0x%08X",
              t, i, used, flags, (int)(short)left, (int)(short)top, width, height,
              (unsigned)param, (unsigned)draw,
              (unsigned)(draw ? draw - delta : 0));
    }

    // The viewport: origin in map pixels, the same pair in tiles, the scroll maxima the
    // clamp compares against, and the map's own size. Together these are the numbers a
    // wider playfield would have to change, so a run records what they actually were.
    {
        unsigned left = 0xFFFF, top = 0xFFFF, tx = 0xFFFF, ty = 0xFFFF;
        unsigned mapTw = 0xFFFF, mapTh = 0xFFFF, mapPw = 0xFFFF, mapPh = 0xFFFF;
        DWORD maxX = 0xFFFFFFFF, maxY = 0xFFFFFFFF;
        ReadU16((DWORD)(DWORD_PTR)Rt(SC_VA_SCREEN_LEFT), &left);
        ReadU16((DWORD)(DWORD_PTR)Rt(SC_VA_SCREEN_TOP), &top);
        ReadU16((DWORD)(DWORD_PTR)Rt(SC_VA_SCREEN_TILE_X), &tx);
        ReadU16((DWORD)(DWORD_PTR)Rt(SC_VA_SCREEN_TILE_Y), &ty);
        ReadU16((DWORD)(DWORD_PTR)Rt(SC_VA_MAP_TILE_W), &mapTw);
        ReadU16((DWORD)(DWORD_PTR)Rt(SC_VA_MAP_TILE_H), &mapTh);
        ReadU16((DWORD)(DWORD_PTR)Rt(SC_VA_MAP_PIXEL_W), &mapPw);
        ReadU16((DWORD)(DWORD_PTR)Rt(SC_VA_MAP_PIXEL_H), &mapPh);
        ReadU32((DWORD)(DWORD_PTR)Rt(SC_VA_SCROLL_MAX_X), &maxX);
        ReadU32((DWORD)(DWORD_PTR)Rt(SC_VA_SCROLL_MAX_Y), &maxY);

        // The prediction, stated in the log rather than only in the document: the clamp is
        // built as (mapTiles - viewportTiles) * 32, with +8 on the vertical axis
        // (0x0049BB90). Printing what it SHOULD be beside what it IS makes a wrong reading
        // of that function visible in the run instead of surviving into research/.
        long predX = ((long)mapTw - SC_VIEWPORT_TILES_X) * 32;
        long predY = ((long)mapTh - SC_VIEWPORT_TILES_Y) * 32 + 8;
        ScLog("SCREEN [%s] origin=(%u,%u) tile=(%u,%u) map=%ux%u tiles (%ux%u px) "
              "scrollMax=(%d,%d) predicted=(%ld,%ld) match=%d",
              t, left, top, tx, ty, mapTw, mapTh, mapPw, mapPh,
              (int)maxX, (int)maxY, predX, predY,
              ((long)(int)maxX == predX && (long)(int)maxY == predY) ? 1 : 0);
    }
}

static void ScanWorld(const char* tag) {
    if (!g_worldScan) return;

    // THE VIEWPORT, first, so a reader can turn every pos=(x,y) below into a CLIENT
    // coordinate: client = map - origin. Without it a script driving the mouse has to
    // guess where the camera is, and a drag box aimed by guesswork picks up whatever
    // else happens to be on screen -- which is how task 024's first in-game run boxed
    // two blocks at once and got the other one's building. The two globals are the ones
    // the engine's own click handler 0x0046FB40 builds its search rectangle from
    // (sc_addresses.h); read-only, and read here rather than hooked. Task 025 needed the
    // same pair for the same reason and arrived at the same two globals independently.
    {
        unsigned left = 0xFFFF, top = 0xFFFF;
        ReadU16((DWORD)(DWORD_PTR)Rt(SC_VA_SCREEN_LEFT), &left);
        ReadU16((DWORD)(DWORD_PTR)Rt(SC_VA_SCREEN_TOP), &top);
        ScLog("WORLD [%s] screen=(%u,%u)", tag ? tag : "-", left, top);
    }

    // EVERY player, including the empty ones, and player 7 last. A reader waits for
    // the p=7 summary to know the whole scan for this marker has landed; skipping
    // empty players would make that signal depend on which slots happen to own units.
    for (int p = 0; p < SC_MAX_PLAYERS; ++p) {
        DWORD head = 0;
        bool  headOk = ReadU32((DWORD)(DWORD_PTR)Rt(SC_VA_PLAYER_UNIT_LIST) + (DWORD)p * 4,
                               &head);

        DWORD unit = headOk ? head : 0;
        int   n = 0, logged = 0;
        bool  walkComplete = headOk && head == 0;
        // Bounded exactly like the fan-out's own reachability walk: never trust a
        // game list to terminate.
        while (unit && n < SC_MAX_UNITS_WALK) {
            if (!WorldUnitPtrValid(unit)) break;
            unsigned type = 0xFFFF, order = 0xFF, order2 = 0xFF, owner = 0xFF, energy = 0xFFFF;
            unsigned stim = 0xFF;
            DWORD hp = 0xFFFFFFFF, flags = 0, sprite = 0;
            unsigned px = 0xFFFF, py = 0xFFFF;

            ReadU16(unit + SC_CUNIT_OFF_UNIT_ID, &type);
            ReadU32(unit + SC_CUNIT_OFF_HITPOINTS, &hp);
            ReadU8(unit + SC_CUNIT_OFF_ORDER_ID, &order);
            ReadU8(unit + SC_CUNIT_OFF_ORDER2_ID, &order2);
            ReadU8(unit + SC_CUNIT_OFF_PLAYER, &owner);
            ReadU16(unit + SC_CUNIT_OFF_ENERGY, &energy);
            ReadU8(unit + SC_CUNIT_OFF_STIM_TIMER, &stim);
            ReadU32(unit + SC_CUNIT_OFF_FLAGS, &flags);
            if (ReadU32(unit + SC_CUNIT_OFF_SPRITE, &sprite) && sprite) {
                ReadU16(sprite + SC_CSPRITE_OFF_POS_X, &px);
                ReadU16(sprite + SC_CSPRITE_OFF_POS_Y, &py);
            }

            if (logged < SC_WORLDSCAN_MAX_LINES) {
                // hp and stim on the SAME line for the same unit: the two halves of a
                // per-unit-cost claim ("it gained the effect AND it paid") are a JOINT
                // property, and two separate histograms can only ever imply the pairing.
                ScLog("WORLD [%s] p=%d i=%d unit=0x%08X owner=%u type=0x%03X hp=%d "
                      "order=0x%02X order2=0x%02X stim=%u energy=%u pos=(%u,%u) "
                      "flags=0x%08X",
                      tag ? tag : "-", p, n, (unsigned)unit, owner, type, (int)hp,
                      order, order2, stim, energy, px, py, (unsigned)flags);
                ++logged;
            }

            DWORD next = 0;
            if (!ReadU32(unit + SC_CUNIT_OFF_LIST_NEXT, &next)) break;
            unit = next;
            ++n;
            if (!next) walkComplete = true;
        }

        // THE CONTROL'S HONESTY CHECK. This runs on the observer thread, so the game
        // thread can head-insert or unlink while the walk is in progress. That cannot
        // fault (every link is validated above and the walk is bounded), but it CAN
        // make one pass MISS a unit that is in play the whole time -- and an undercount
        // in an order-stability measurement looks exactly like the defect being hunted
        // ("a unit stopped existing"). So the count is taken a second time and both are
        // reported: a reader that sees `units=13 recount=13 complete=1` knows the sample
        // was not torn, and one that sees a disagreement knows to discard it rather than
        // to believe it. Sampling on the game thread would be better still, and is not
        // available here on purpose -- it would need a hook, and the stock arm of this
        // comparison must install none.
        bool recountOk = false;
        int  recount = CountPlayerUnits(p, &recountOk);
        ScLog("WORLD [%s] p=%d units=%d recount=%d complete=%d%s",
              tag ? tag : "-", p, n, recount,
              (walkComplete && recountOk) ? 1 : 0,
              n > logged ? " (per-unit lines above truncated)" : "");
    }
}

// ---------------------------------------------------------------------------
// Marker channel
//
// Correlating "what I did on screen" with "what the log says" after the fact is
// the whole point of the exercise, and timestamps alone are ambiguous once the
// game is running at 250ms poll granularity. The driver writes a one-line label
// into a marker file before each test case; the observer notices the change and
// stamps it into the log, in-band, between the snapshots it separates.
//
// This is a read of a file the observer owns -- it is not a write to, or a hook
// into, the game.
// ---------------------------------------------------------------------------

static char g_markerPath[MAX_PATH];
static char g_lastMarker[256];

static void ResolveMarkerPath(void) {
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_MARKER", g_markerPath, MAX_PATH);
    if (n != 0 && n < MAX_PATH) return;

    char logPath[MAX_PATH];
    ScLogResolvePath(logPath, sizeof(logPath));
    char* slash = strrchr(logPath, '\\');
    if (slash) {
        *(slash + 1) = '\0';
        _snprintf(g_markerPath, MAX_PATH - 1, "%smarker.txt", logPath);
    } else {
        lstrcpynA(g_markerPath, "marker.txt", MAX_PATH);
    }
    g_markerPath[MAX_PATH - 1] = '\0';
}

static void PollMarker(void) {
    HANDLE h = CreateFileA(g_markerPath, GENERIC_READ,
                           FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                           NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return;

    char buf[256] = {0};
    DWORD got = 0;
    ReadFile(h, buf, sizeof(buf) - 1, &got, NULL);
    CloseHandle(h);
    buf[got < sizeof(buf) ? got : sizeof(buf) - 1] = '\0';

    for (char* p = buf; *p; ++p) if (*p == '\r' || *p == '\n') { *p = '\0'; break; }
    if (buf[0] == '\0') return;
    if (strcmp(buf, g_lastMarker) == 0) return;

    lstrcpynA(g_lastMarker, buf, sizeof(g_lastMarker));
    ScLog("---- MARK: %s ----", g_lastMarker);

    // Task 022: the world scan fires on the same trigger, and BEFORE the shadow dump,
    // so a run that reads both gets the engine's own view first. It is the only oracle
    // that exists in observe mode, which is the stock arm of the plugin-vs-stock
    // comparison.
    ScanWorld(g_lastMarker);

    // Task 026: and so does the command-card read-back. It goes BEFORE the shadow
    // dump for the same reason the world scan does -- the engine's own view first.
    ScCardScan(g_lastMarker);

    // Task 032: the renderer's own view of itself. Same trigger, same read-only shape.
    ScanScreen(g_lastMarker);

    // Task 015: a marker is the driver saying "look now", so it is also the trigger for
    // the per-unit state dump. Driving it off the marker rather than off a timer is what
    // makes an unattended assertion possible at all -- the test writes a marker, waits for
    // the UNITSTATE line carrying that exact tag, and asserts on it. No polling race, and
    // no extra IPC beyond the file channel that already exists.
    ScFanoutLogUnitStates(g_lastMarker);

    // Task 025: the production-queue oracle, on the same trigger and for the same
    // reason. It prints the ENGINE's own five slots read straight out of CUnit+0x98
    // beside the plugin's overflow, so an unattended run asserts a queue length from
    // the building's memory rather than from the screen. Read-only; a no-op when
    // %SCPLUGIN_PRODQ% never switched the feature on.
    ScProdQueueLogState(g_lastMarker);
}

// ---------------------------------------------------------------------------
// Active-dialog scan (task 027) -- READ-ONLY
//
// Why it exists: every in-game suite dismissed the "StarCraft Tips" dialog by
// clicking a HARDCODED point (200,261) with no check that a dialog was ever there
// and no check that it went away. That is the same shape as the map-browser
// row-by-number bug this repo already has a hard rule about. With the dialog list
// readable, a suite can find the tips dialog, click ITS OWN OK button wherever the
// engine put it, and assert the dialog is gone.
//
// The walk is the engine's own: head at SC_VA_DIALOG_LIST, "next" at +0x00, controls
// from +0x42, each with text at +0x14 and bounds at +0x04 -- the layout sc_hudrow
// already reads (sc_addresses.h carries the per-offset evidence). Every read goes
// through SafeRead, so a wrong offset produces a missing field, never a fault inside
// the game. Nothing here writes, hooks or calls into the game.
//
// One line per CHANGE of the dialog set, not per tick: a menu that sits still logs
// once. %SCPLUGIN_DIALOGS%=0 turns it off.
// ---------------------------------------------------------------------------

static bool g_dialogScan = true;

// Copies a NUL-terminated string out of the game, one byte at a time through
// SafeRead, and sanitises it for the log: dialog text is game data, so a stray
// newline or '|' would corrupt the line a parser is about to read.
static void ReadDlgText(DWORD ptr, char* out, size_t outLen) {
    out[0] = '\0';
    if (!ptr || outLen < 2) return;
    size_t i = 0;
    for (; i + 1 < outLen; ++i) {
        BYTE c = 0;
        if (!SafeRead((const void*)(ptr + i), &c, 1)) break;
        if (c == 0) break;
        out[i] = (c < 32 || c > 126 || c == '|' || c == '\'') ? '.' : (char)c;
    }
    out[i] = '\0';
}

// left,top,right,bottom -- four s16 at +0x04 (SC_BINDLG_OFF_BOUNDS).
static void ReadDlgRect(DWORD dlg, int* r) {
    for (int i = 0; i < 4; ++i) {
        unsigned v = 0;
        r[i] = ReadU16(dlg + SC_BINDLG_OFF_BOUNDS + (unsigned)i * 2, &v) ? (int)(short)v : -1;
    }
}

static void ScanDialogs(void) {
    if (!g_dialogScan) return;

    static char prev[2048] = { 0 };
    char line[2048];
    size_t used = 0;
    line[0] = '\0';

    DWORD dlg = 0;
    int n = 0;
    if (ReadU32((DWORD)(DWORD_PTR)Rt(SC_VA_DIALOG_LIST), &dlg)) {
        while (dlg && n < SC_MAX_DIALOGS_WALK) {
            char name[64];
            DWORD text = 0;
            ReadU32(dlg + SC_BINDLG_OFF_TEXT, &text);
            ReadDlgText(text, name, sizeof(name));
            int r[4];
            ReadDlgRect(dlg, r);

            int w = _snprintf(line + used, sizeof(line) - used, "%s dlg='%s' rect=%d,%d,%d,%d",
                              used ? " |" : "", name, r[0], r[1], r[2], r[3]);
            if (w < 0 || (size_t)w >= sizeof(line) - used) break;
            used += (size_t)w;

            // The controls, so a caller can aim at the real OK button. Only the ones
            // that carry text -- the artwork children are noise for that job.
            DWORD ctrl = 0;
            ReadU32(dlg + SC_BINDLG_OFF_FIRST_CHILD, &ctrl);
            int c = 0;
            while (ctrl && c < SC_MAX_CTRLS_WALK) {
                char ctext[64];
                DWORD ct = 0;
                ReadU32(ctrl + SC_BINDLG_OFF_TEXT, &ct);
                ReadDlgText(ct, ctext, sizeof(ctext));
                if (ctext[0]) {
                    int cr[4];
                    ReadDlgRect(ctrl, cr);
                    unsigned flags = 0, type = 0;
                    ReadU32(ctrl + SC_BINDLG_OFF_FLAGS, (DWORD*)&flags);
                    ReadU16(ctrl + SC_BINDLG_OFF_TYPE, &type);
                    int cw = _snprintf(line + used, sizeof(line) - used,
                                       " ctrl='%s' rect=%d,%d,%d,%d type=%u flags=0x%X",
                                       ctext, cr[0], cr[1], cr[2], cr[3], type, flags);
                    if (cw < 0 || (size_t)cw >= sizeof(line) - used) break;
                    used += (size_t)cw;
                }
                DWORD next = 0;
                if (!ReadU32(ctrl + SC_BINDLG_OFF_NEXT, &next)) break;
                ctrl = next;
                ++c;
            }

            DWORD next = 0;
            if (!ReadU32(dlg + SC_BINDLG_OFF_NEXT, &next)) break;
            dlg = next;
            ++n;
        }
    }

    if (strcmp(line, prev) == 0) return;
    strncpy(prev, line, sizeof(prev) - 1);
    prev[sizeof(prev) - 1] = '\0';
    ScLog("DIALOGS n=%d%s%s", n, n ? " " : "", line);
}

// ---------------------------------------------------------------------------
// Observer thread
// ---------------------------------------------------------------------------

static DWORD GetPollMs(void) {
    char buf[32];
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_POLL_MS", buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return 250;
    int v = atoi(buf);
    if (v < 20) v = 20;
    if (v > 5000) v = 5000;
    return (DWORD)v;
}

static ScMode g_mode = SC_MODE_OBSERVE;

static bool GetWorldScan(void) {
    char buf[16];
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_WORLDSCAN", buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return false;
    return buf[0] == '1' || buf[0] == 'y' || buf[0] == 'Y';
}

// ON by default, unlike the world scan: it logs one line per CHANGE of the dialog
// set, so a whole run adds a handful of lines, and the tips-dialog dismissal in
// every suite depends on it.
static bool GetDialogScan(void) {
    char buf[16];
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_DIALOGS", buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return true;
    return !(buf[0] == '0' || buf[0] == 'n' || buf[0] == 'N');
}

// OFF by default, same shape as the world scan: %SCPLUGIN_CARDSCAN%=1 turns on the
// read-only command-card walk (task 026).
static bool GetCardScan(void) {
    char buf[16];
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_CARDSCAN", buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return false;
    return buf[0] == '1' || buf[0] == 'y' || buf[0] == 'Y';
}

// OFF by default, same shape as the world scan and for the same reason: %SCPLUGIN_SCREENSCAN%=1
// turns on the read-only renderer/viewport read-back (task 032).
static bool GetScreenScan(void) {
    char buf[16];
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_SCREENSCAN", buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return false;
    return buf[0] == '1' || buf[0] == 'y' || buf[0] == 'Y';
}

static DWORD WINAPI ObserverThread(LPVOID) {
    const DWORD pollMs = GetPollMs();
    g_worldScan = GetWorldScan();
    g_screenScan = GetScreenScan();
    g_dialogScan = GetDialogScan();
    // Task 026: the read-only command-card scan. Same shape and same off switch as
    // the world scan, and for the same reason -- it must exist in observe mode too,
    // because "the card the stock game draws" is half of every comparison.
    ScCardInit(g_base, GetCardScan());
    ResolveMarkerPath();
    ScLog("OBSERVER start pollMs=%u mode=%s%s", (unsigned)pollMs, ScModeName(g_mode),
          g_mode == SC_MODE_OBSERVE ? " (read-only; no writes to game memory)" : "");
    ScLog("OBSERVER marker file: %s", g_markerPath);
    ScLog("OBSERVER worldScan=%d (%%SCPLUGIN_WORLDSCAN%%; read-only walk of the engine's "
          "own per-player unit lists, installs no hook and works in observe mode)",
          g_worldScan ? 1 : 0);
    ScLog("OBSERVER cardScan=%d (%%SCPLUGIN_CARDSCAN%%; read-only walk of the command-card "
          "dialog 0x0068C148, installs no hook and works in observe mode)",
          ScCardEnabled() ? 1 : 0);
    ScLog("OBSERVER screenScan=%d (%%SCPLUGIN_SCREENSCAN%%; read-only read-back of the screen "
          "Bitmap 0x006CEFF0, the 8 graphic layers 0x006CEF50 and the scroll clamp, installs "
          "no hook and works in observe mode)",
          g_screenScan ? 1 : 0);

    Snapshot prev;
    memset(&prev, 0xFF, sizeof(prev));  // force a first log line
    unsigned ticks = 0;

    while (!InterlockedCompareExchange(&g_stop, 0, 0)) {
        PollMarker();
        ScanDialogs();
        Snapshot cur;
        TakeSnapshot(&cur);
        // memcmp compares the padding bytes too, so `prev` must be refreshed with
        // a byte copy. Struct assignment is not required to carry padding across;
        // a compiler that dropped it would leave `prev`'s 0xFF seed in the gaps
        // forever and every tick would look like a change.
        if (memcmp(&cur, &prev, sizeof(cur)) != 0) {
            LogSnapshot(&cur);
            memcpy(&prev, &cur, sizeof(prev));
        }
        // Liveness heartbeat: proves the thread is still polling during long
        // stretches with no selection change (menus, loading screens).
        if (++ticks % (60000 / pollMs ? 60000 / pollMs : 1) == 0) {
            ScLog("HEARTBEAT ticks=%u", ticks);
            ScFanoutLogState();
        }
        Sleep(pollMs);
    }

    ScLog("OBSERVER stop ticks=%u", ticks);
    return 0;
}

// ---------------------------------------------------------------------------
// Attach
// ---------------------------------------------------------------------------

static void LogAttachBanner(void) {
    HMODULE exeMod = GetModuleHandleA(NULL);
    g_base = (BYTE*)exeMod;

    char exePath[MAX_PATH] = {0};
    GetModuleFileNameA(exeMod, exePath, MAX_PATH);

    char dllPath[MAX_PATH] = {0};
    HMODULE self = NULL;
    GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                       GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       (LPCSTR)&LogAttachBanner, &self);
    if (self) GetModuleFileNameA(self, dllPath, MAX_PATH);

    LONG delta = (LONG)((DWORD_PTR)g_base - SC_PREFERRED_IMAGE_BASE);

    ScLog("========================================================");
    ScLog("ATTACH pid=%u tid=%u", (unsigned)GetCurrentProcessId(),
          (unsigned)GetCurrentThreadId());
    ScLog("  host exe      : %s", exePath);
    ScLog("  plugin dll    : %s", dllPath);
    ScLog("  module base   : 0x%08X", (unsigned)(DWORD_PTR)g_base);
    ScLog("  preferred base: 0x%08X", (unsigned)SC_PREFERRED_IMAGE_BASE);
    ScLog("  reloc delta   : %s0x%08X  => static addresses are %s",
          delta < 0 ? "-" : "+", (unsigned)(delta < 0 ? -delta : delta),
          delta == 0 ? "USABLE VERBATIM" : "SHIFTED (rebased by the plugin)");

    // Read a couple of bytes at the image base as a sanity check that we are
    // reading the mapped image at all ('MZ' == 0x5A4D).
    WORD mz = 0;
    if (SafeRead(g_base, &mz, 2)) {
        ScLog("  image[0..1]   : 0x%04X %s", mz,
              mz == 0x5A4D ? "('MZ' - mapped image confirmed)" : "(UNEXPECTED)");
    } else {
        ScLog("  image[0..1]   : UNREADABLE");
    }
    ScLog("  mode          : %s (%%SCPLUGIN_MODE%%; unset => observe, which writes "
          "nothing to game memory)", ScModeName(g_mode));
}

static HANDLE g_observer = NULL;

BOOL WINAPI DllMain(HINSTANCE hinst, DWORD reason, LPVOID lpReserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hinst);
        ScLogOpen();
        g_mode = ScFanoutResolveMode();
        LogAttachBanner();
        ScFanoutInstall(g_base, g_mode);
        // Task 025. Gated on %SCPLUGIN_PRODQ% AND on not being in observe mode:
        // observe is the whole plugin's off switch and must stay byte-for-byte the
        // task-008 read-only observer, whatever else is set in the environment.
        if (g_mode == SC_MODE_OBSERVE) {
            if (ScProdQueueEnabled()) {
                ScLog("PRODQ: %%SCPLUGIN_PRODQ%% is set but the mode is observe -- "
                      "IGNORED. Observe writes nothing to game memory.");
            }
        } else {
            ScProdQueueInstall(g_base);
        }
        // The observer runs on its own thread; DllMain itself does nothing but
        // start it, so we never hold the loader lock while polling.
        g_observer = CreateThread(NULL, 0, ObserverThread, NULL, 0, NULL);
        if (!g_observer) ScLog("ERROR CreateThread failed gle=%u",
                               (unsigned)GetLastError());
    } else if (reason == DLL_PROCESS_DETACH) {
        InterlockedExchange(&g_stop, 1);

        // lpReserved == NULL means FreeLibrary: the observer thread is still
        // running and this DLL's code is about to be unmapped underneath it, so
        // it has to be joined before the log handle and the lock are destroyed.
        // The thread only calls file, memory and Sleep APIs -- never LoadLibrary
        // or FreeLibrary -- so it cannot be waiting on the loader lock DllMain
        // holds, and this bounded wait cannot deadlock against it.
        //
        // lpReserved != NULL means the process is exiting: Windows has already
        // terminated every other thread, so there is nothing to join, and the
        // log lock may be permanently owned by a thread that no longer exists.
        bool joined = true;
        if (lpReserved != NULL) ScLogSetTryLock();
        ScFanoutLogStats();   // the run's counters, on both detach paths
        ScProdQueueLogStats();
        if (lpReserved == NULL) {
            if (g_observer) joined = (WaitForSingleObject(g_observer, 5000) == WAIT_OBJECT_0);
            // Un-splice only on the FreeLibrary path. On process exit the address
            // space is being torn down anyway, and walking the thread list from
            // DllMain under the loader lock is exactly the kind of call that is
            // documented as unsafe there.
            //
            // ScProdQueueRemove goes FIRST: it refunds every overflow item it is still
            // holding before it un-splices. The other order would leave paid-for items
            // with no hook left to promote or refund them.
            ScProdQueueRemove();
            ScFanoutRemove();
        }

        ScLog("DETACH pid=%u", (unsigned)GetCurrentProcessId());

        if (joined) {
            if (g_observer) { CloseHandle(g_observer); g_observer = NULL; }
            ScLogClose();
        }
        // If the join timed out, the handles and the critical section are leaked
        // on purpose: a thread that may still be logging must not find them
        // closed. A leak at unload is strictly better than a use-after-free
        // inside the game.
    }
    return TRUE;
}
