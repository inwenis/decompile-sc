// scplugin.cpp -- StarCraft 1.16.1 plugin DLL, injected into a running StarCraft.exe.
// It polls the selection globals mapped in research/binary-selection-map.md and logs
// each observed change. %SCPLUGIN_MODE% selects how much more it does; every module that
// writes to game memory is gated out of observe:
//   observe   (DEFAULT)  read-only: no hooks, no writes. THIS IS THE OFF SWITCH.
//   hooktest             one hook (queueCommand), logging only
//   fanout               + capture the pre-cap selection and fan orders out over it
// Unset or unrecognised -> observe: the plugin is passive unless asked for more.
//
// It never patches StarCraft.exe on disk; every modification lives in this process's
// memory and is undone on unload.
//
// Log destination: %SCPLUGIN_LOG%, else C:\sc-work\logs\sc-plugin.log -- outside the
// repo and gitignored, so no captured game data is committed (AGENTS.md § "Hard rules").

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sc_addresses.h"
#include "sc_buildid.h"
#include "sc_card.h"
#include "sc_console.h"
#include "sc_marktrace.h"
#include "sc_engine.h"
#include "sc_env.h"
#include "sc_fanout.h"
#include "sc_hook.h"
#include "sc_log.h"
#include "sc_mode.h"
#include "sc_prodfan.h"
#include "sc_prodqueue.h"
#include "sc_queueind.h"
#include "sc_screen.h"
#include "sc_session.h"
#include "sc_unit.h"
#include "sc_stormpresent.h"
#include "sc_upgrades.h"

static volatile LONG g_stop = 0;

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

    if (ScSafeRead(ScRuntimeAddr(SC_VA_CLIENT_SELECTION_COUNT), &s->count, 1)) s->ok |= OK_COUNT;
    ScSafeRead(ScRuntimeAddr(SC_VA_SELECTION_ITERATOR), &s->iterator, 1);

    if (ScSafeRead(ScRuntimeAddr(SC_VA_ACTIVE_PLAYER_ID), &s->playerId, 4) &&
        ScSafeRead(ScRuntimeAddr(SC_VA_PLAYER_ID_512688), &s->playerId688, 4) &&
        ScSafeRead(ScRuntimeAddr(SC_VA_PLAYER_ID_512678), &s->playerId678, 4)) {
        s->ok |= OK_IDS;
    }

    if (ScSafeRead(ScRuntimeAddr(SC_VA_CLIENT_SELECTION_GROUP), s->group, sizeof(s->group)))
        s->ok |= OK_GROUP;
    if (ScSafeRead(ScRuntimeAddr(SC_VA_CLIENT_SELECTION_GROUP2), s->group2, sizeof(s->group2)))
        s->ok |= OK_GROUP2;
    if (ScSafeRead(ScRuntimeAddr(SC_VA_ACTIVE_PLAYER_SELECTION), s->active, sizeof(s->active)))
        s->ok |= OK_ACTIVE;

    // playersSelections[player] -- clamp the index: the player id is read out of game
    // memory and is exactly the kind of value to check rather than trust.
    DWORD p = (s->ok & OK_IDS) ? (s->playerId & 0xFF) : 0;
    if (p < SC_MAX_PLAYERS) {
        DWORD rowVa = SC_VA_PLAYERS_SELECTIONS + p * SC_SELECTION_SLOTS * 4;
        if (ScSafeRead(ScRuntimeAddr(rowVa), s->playerRow, sizeof(s->playerRow))) s->ok |= OK_ROW;
    }
}

// One tagged line holding all three selection layers, written on the marker rather than
// on change (see the call site). Counts are non-NULL entries, the engine's own
// termination rule for these arrays -- they are filled densely from slot 0 and every
// walker in the binary stops at the first NULL.
static void LogSelectionArrays(const char* tag) {
    Snapshot s;
    TakeSnapshot(&s);
    char gbuf[512], abuf[512], rbuf[512];
    FormatSlots(s.group,     gbuf, sizeof(gbuf));
    FormatSlots(s.active,    abuf, sizeof(abuf));
    FormatSlots(s.playerRow, rbuf, sizeof(rbuf));
    ScLog("SELSNAP [%s] client=%d clientCount=%u active=%d sim=%d player=%u ok=0x%02X",
          tag ? tag : "-", NonNull(s.group), (unsigned)s.count, NonNull(s.active),
          NonNull(s.playerRow), (unsigned)(s.playerId & 0xFF), (unsigned)s.ok);
    ScLog("    SELSNAP clientSelectionGroup   %s", gbuf);
    ScLog("    SELSNAP activePlayerSelection  %s", abuf);
    ScLog("    SELSNAP playersSelections      %s", rbuf);
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
// World scan -- READ-ONLY, and deliberately INDEPENDENT of the hooks
//
// The fan-out's UNITSTATE line walks the SHADOW list, so it exists only in a mode that
// installs hooks. "Does the game behave differently with our plugin in it?" needs an
// oracle that also works in `-Mode observe`, the fully stock control arm: an oracle
// that exists on only one side of that comparison cannot answer it. So this walks the
// ENGINE's own per-player unit lists (playerUnitList, SC_VA_PLAYER_UNIT_LIST, threaded
// on CUnit+0x6C -- sc_addresses.h). Every read goes through SafeRead, so a wrong offset
// produces a missing field, never a fault; nothing here writes, hooks or calls in.
//
// Off by default (%SCPLUGIN_WORLDSCAN%, launcher flag -WorldScan 1): the suites parse
// this log, and a fixture with 36 units adds 36 lines per marker to every run.
// ---------------------------------------------------------------------------

static bool g_worldScan = false;

// Per player, so one runaway list cannot bury the log. A fixture big enough to hit
// this is a fixture whose per-unit detail was never going to be readable anyway.
#define SC_WORLDSCAN_MAX_LINES 64

static bool ReadU8(DWORD addr, unsigned* out) {
    BYTE v = 0;
    if (!ScSafeRead((const void*)addr, &v, 1)) return false;
    *out = v;
    return true;
}

static bool ReadU16(DWORD addr, unsigned* out) {
    WORD v = 0;
    if (!ScSafeRead((const void*)addr, &v, 2)) return false;
    *out = v;
    return true;
}

static bool ReadU32(DWORD addr, DWORD* out) {
    DWORD v = 0;
    if (!ScSafeRead((const void*)addr, &v, 4)) return false;
    *out = v;
    return true;
}

// Counts one player's list without logging -- the recount pass; see ScanWorld.
static int CountPlayerUnits(int p, bool* ok) {
    DWORD head = 0;
    *ok = false;
    if (!ReadU32(ScRuntimeVa(SC_VA_PLAYER_UNIT_LIST) + (DWORD)p * 4, &head))
        return 0;
    int n = 0;
    for (DWORD u = head; u && n < SC_MAX_UNITS_WALK; ) {
        if (!ScUnitPtrValid(u)) return n;
        DWORD next = 0;
        if (!ReadU32(u + SC_CUNIT_OFF_LIST_NEXT, &next)) return n;
        u = next;
        ++n;
    }
    *ok = true;
    return n;
}

// ---------------------------------------------------------------------------
// Screen/viewport scan -- READ-ONLY
//
// research/renderer-viewport.md is a static map, and a static map is a prediction until
// the running process confirms it (AGENTS.md § "Claims about the binary"). So every
// number it asserts about the live layout -- the screen Bitmap's width/height/pointer,
// each layer's rectangle and draw callback, the scroll maxima, the tile-granular origin
// -- is printed here out of the process, to be quoted back beside the disassembly it was
// predicted from.
//
// No hook, no calls into the game, no writes, so it runs in -Mode observe. Off by default
// (%SCPLUGIN_SCREENSCAN%, launcher flag -ScreenScan 1): it adds ten lines per marker to a
// log the suites parse.
//
// Layer draw callbacks print as STATIC VAs (runtime minus the relocation delta) so they
// compare directly against sc_addresses.h and the Ghidra listing.
// ---------------------------------------------------------------------------

static bool g_screenScan = false;

static void ScanScreen(const char* tag) {
    if (!g_screenScan) return;
    const char* t = tag ? tag : "-";
    const DWORD delta = (DWORD)(DWORD_PTR)ScEngineModuleBase() - SC_PREFERRED_IMAGE_BASE;

    // The screen Bitmap. `data` is the 640*480 SMemAlloc from 0x004DB060; a non-zero value
    // here is the evidence that the buffer exists and that the descriptor is the live one.
    {
        DWORD b = ScRuntimeVa(SC_VA_SCREEN_BITMAP);
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
        DWORD l = ScRuntimeVa(SC_VA_GRAPHIC_LAYERS) + (DWORD)i * SC_LAYER_STRIDE;
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
        ReadU16(ScRuntimeVa(SC_VA_SCREEN_LEFT), &left);
        ReadU16(ScRuntimeVa(SC_VA_SCREEN_TOP), &top);
        ReadU16(ScRuntimeVa(SC_VA_SCREEN_TILE_X), &tx);
        ReadU16(ScRuntimeVa(SC_VA_SCREEN_TILE_Y), &ty);
        ReadU16(ScRuntimeVa(SC_VA_MAP_TILE_W), &mapTw);
        ReadU16(ScRuntimeVa(SC_VA_MAP_TILE_H), &mapTh);
        ReadU16(ScRuntimeVa(SC_VA_MAP_PIXEL_W), &mapPw);
        ReadU16(ScRuntimeVa(SC_VA_MAP_PIXEL_H), &mapPh);
        ReadU32(ScRuntimeVa(SC_VA_SCROLL_MAX_X), &maxX);
        ReadU32(ScRuntimeVa(SC_VA_SCROLL_MAX_Y), &maxY);

        // The prediction, stated in the log rather than only in the document: the clamp is
        // built as (mapTiles - viewportTiles) * 32, plus a vertical bias that keeps the
        // stock 24 px overscroll (0x0049BB90). Printing what it SHOULD be beside what it IS
        // makes a wrong reading of that function visible in the run instead of surviving
        // into research/. Both axes come from the live geometry (20x12 tiles and +8 stock;
        // the table's playfield when widescreen is patched in): a prediction pinned at the
        // stock values prints match=0 against a correct widened clamp.
        const int vpTilesX = ScScreenViewportTilesX();
        long predX = ((long)mapTw - vpTilesX) * 32;
        long predY = ((long)mapTh - ScScreenViewportTilesY()) * 32 + ScScreenScrollBiasY();
        ScLog("SCREEN [%s] origin=(%u,%u) tile=(%u,%u) map=%ux%u tiles (%ux%u px) "
              "scrollMax=(%d,%d) predicted=(%ld,%ld) vpTilesX=%d match=%d",
              t, left, top, tx, ty, mapTw, mapTh, mapPw, mapPh,
              (int)maxX, (int)maxY, predX, predY, vpTilesX,
              ((long)(int)maxX == predX && (long)(int)maxY == predY) ? 1 : 0);
    }
}

// ---------------------------------------------------------------------------
// Framebuffer dump -- READ-ONLY
//
// The PRESENTED window is WMode.dll's columns 0..639 of whatever the engine composed
// (research/renderer-viewport.md 12.6, 12.10), so no capture of it can see the right 160
// columns of an 800-wide frame. This reads the engine's OWN composed frame -- the screen
// Bitmap 0x006CEFF0 (u16 w, u16 h, u8* data; pitch == width, research/renderer-viewport.md
// 2) -- out of process memory, without presenting it and without touching the display.
//
// Same family as the SCREEN scan above: no hook, no writes, so it exists in -Mode observe.
// Off by default: %SCPLUGIN_FRAMEDUMP% names the directory (launcher flag -FrameDump).
// THE DUMP REPRODUCES GAME ARTWORK, so that directory must be on the gitignored diagnostic
// path (C:\sc-work\...) and no dump is ever committed -- the same rules as for a PNG, in a
// different container (AGENTS.md § "Screenshots").
//
// TEARING. The observer reads while the game thread composes, so one copy can be half of
// one frame and half of the next. The dump therefore copies until two CONSECUTIVE copies
// are byte-equal -- equality means no compose landed between the first copy's start and
// the second copy's end, i.e. the pair straddles a settled frame -- and reports how many
// reads that took (reads=) and whether it ever settled (stable=). A dump that never
// settled is still written (it is evidence), with stable=0 on its line and in its header,
// so a consumer can refuse it rather than trust it silently.
// ---------------------------------------------------------------------------

static bool g_frameDump = false;
static char g_frameDumpDir[MAX_PATH];

static bool GetFrameDump(void) {
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_FRAMEDUMP", g_frameDumpDir,
                                      sizeof(g_frameDumpDir));
    if (n == 0 || n >= sizeof(g_frameDumpDir)) { g_frameDumpDir[0] = '\0'; return false; }
    // Last component only; the parent (C:\sc-work\logs) exists on every machine
    // this runs on, and a caller pointing somewhere deeper owns that path.
    CreateDirectoryA(g_frameDumpDir, NULL);
    return true;
}

// One copy of the whole frame, row by row through SafeRead: the buffer is a
// heap allocation and SafeRead refuses ranges that cross a region boundary,
// which a 307200/384000-byte block legitimately can.
static bool CopyFrameRows(DWORD bits, unsigned w, unsigned h, BYTE* dst) {
    for (unsigned y = 0; y < h; ++y) {
        if (!ScSafeRead((const void*)(DWORD_PTR)(bits + y * w), dst + (size_t)y * w, w))
            return false;
    }
    return true;
}

static void DumpFrame(const char* tag) {
    if (!g_frameDump) return;
    const char* t = tag ? tag : "-";

    DWORD b = ScRuntimeVa(SC_VA_SCREEN_BITMAP);
    unsigned w = 0, h = 0;
    DWORD data = 0;
    if (!ReadU16(b + SC_BITMAP_OFF_WIDTH, &w) || !ReadU16(b + SC_BITMAP_OFF_HEIGHT, &h) ||
        !ReadU32(b + SC_BITMAP_OFF_DATA, &data)) {
        ScLog("FRAMEDUMP [%s] refused: descriptor at 0x%08X unreadable", t,
              (unsigned)SC_VA_SCREEN_BITMAP);
        return;
    }
    // The dump trusts the descriptor for its geometry, so an insane descriptor is
    // a refusal rather than a gigantic read. 64..4096 brackets every size this
    // project will ever patch in and excludes the zeroed pre-video-init state.
    if (data == 0 || w < 64 || w > 4096 || h < 64 || h > 4096) {
        ScLog("FRAMEDUMP [%s] refused: descriptor implausible w=%u h=%u data=0x%08X",
              t, w, h, (unsigned)data);
        return;
    }

    const size_t n = (size_t)w * h;
    BYTE* cur  = (BYTE*)malloc(n);
    BYTE* next = (BYTE*)malloc(n);
    if (!cur || !next) {
        free(cur); free(next);
        ScLog("FRAMEDUMP [%s] refused: alloc of %u bytes failed", t, (unsigned)n);
        return;
    }

    int  reads = 0;
    bool stable = false;
    bool readOk = CopyFrameRows(data, w, h, cur);
    if (readOk) {
        ++reads;
        // The pair must straddle a settled frame, so the bigger the buffer the more
        // tries it takes: a 1280x880 copy is ~3.7x a stock 640x480 one, so more
        // compose frames land between two reads on an animating menu, and 8 tries
        // (the stock budget) started missing at the taller geometry. Scale the cap
        // with the read cost so a wide/tall frame gets proportionally more attempts.
        const int kBudget = 7 + (int)(n / (640u * 480u)) * 8;
        for (int i = 0; i < kBudget && !stable; ++i) {
            if (!CopyFrameRows(data, w, h, next)) { readOk = false; break; }
            ++reads;
            if (memcmp(cur, next, n) == 0) stable = true;
            else { BYTE* s = cur; cur = next; next = s; }   // keep the LATEST in cur
        }
    }
    if (!readOk) {
        ScLog("FRAMEDUMP [%s] refused: buffer read failed after %d read(s) "
              "(w=%u h=%u data=0x%08X)", t, reads, w, h, (unsigned)data);
        free(cur); free(next);
        return;
    }

    char name[96];
    unsigned ni = 0;
    for (const char* p = t; *p && ni < sizeof(name) - 1; ++p) {
        char c = *p;
        name[ni++] = ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                      (c >= '0' && c <= '9') || c == '-' || c == '_') ? c : '-';
    }
    name[ni] = '\0';
    char path[MAX_PATH];
    _snprintf(path, sizeof(path) - 1, "%s\\fd-%s.bin", g_frameDumpDir, name);
    path[sizeof(path) - 1] = '\0';

    // 16-byte header, then the pixels row-major with pitch == width:
    //   'SCFD'  u16 w  u16 h  u32 pixelBytes  u16 reads  u16 stable
    BYTE hdr[16];
    hdr[0] = 'S'; hdr[1] = 'C'; hdr[2] = 'F'; hdr[3] = 'D';
    *(WORD*)(hdr + 4)  = (WORD)w;
    *(WORD*)(hdr + 6)  = (WORD)h;
    *(DWORD*)(hdr + 8) = (DWORD)n;
    *(WORD*)(hdr + 12) = (WORD)reads;
    *(WORD*)(hdr + 14) = (WORD)(stable ? 1 : 0);

    HANDLE f = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                           FILE_ATTRIBUTE_NORMAL, NULL);
    bool wrote = false;
    if (f != INVALID_HANDLE_VALUE) {
        DWORD out = 0;
        wrote = WriteFile(f, hdr, sizeof(hdr), &out, NULL) && out == sizeof(hdr);
        if (wrote) {
            wrote = WriteFile(f, cur, (DWORD)n, &out, NULL) && out == (DWORD)n;
        }
        CloseHandle(f);
    }
    if (!wrote) {
        ScLog("FRAMEDUMP [%s] refused: could not write %s (gle=%u)", t, path,
              (unsigned)GetLastError());
    } else {
        ScLog("FRAMEDUMP [%s] w=%u h=%u bytes=%u reads=%d stable=%d path=%s",
              t, w, h, (unsigned)n, reads, stable ? 1 : 0, path);
    }
    free(cur); free(next);
}

static void ScanWorld(const char* tag) {
    if (!g_worldScan) return;

    // THE VIEWPORT, first, so a reader can turn every pos=(x,y) below into a CLIENT
    // coordinate: client = map - origin. Without it a script driving the mouse has to
    // guess where the camera is, and a drag box aimed by guesswork picks up whatever else
    // is on screen -- measured once as two unit blocks boxed at once and the wrong
    // building selected. Both globals are the ones the engine's own click handler
    // 0x0046FB40 builds its search rectangle from (sc_addresses.h).
    {
        unsigned left = 0xFFFF, top = 0xFFFF;
        ReadU16(ScRuntimeVa(SC_VA_SCREEN_LEFT), &left);
        ReadU16(ScRuntimeVa(SC_VA_SCREEN_TOP), &top);
        ScLog("WORLD [%s] screen=(%u,%u)", tag ? tag : "-", left, top);
    }

    // EVERY player, including the empty ones, and player 7 last. A reader waits for
    // the p=7 summary to know the whole scan for this marker has landed; skipping
    // empty players would make that signal depend on which slots happen to own units.
    for (int p = 0; p < SC_MAX_PLAYERS; ++p) {
        DWORD head = 0;
        bool  headOk = ReadU32(ScRuntimeVa(SC_VA_PLAYER_UNIT_LIST) + (DWORD)p * 4,
                               &head);

        DWORD unit = headOk ? head : 0;
        int   n = 0, logged = 0;
        bool  walkComplete = headOk && head == 0;
        // Bounded exactly like the fan-out's own reachability walk: never trust a
        // game list to terminate.
        while (unit && n < SC_MAX_UNITS_WALK) {
            if (!ScUnitPtrValid(unit)) break;
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
        // thread can head-insert or unlink mid-walk. That cannot fault (every link is
        // validated above and the walk is bounded) but it CAN make one pass MISS a unit
        // that is in play the whole time -- and an undercount in an order-stability
        // measurement looks exactly like the defect being hunted ("a unit stopped
        // existing"). So the count is taken twice: `units=13 recount=13 complete=1` says
        // the sample was not torn, a disagreement says to discard it. Sampling on the
        // game thread is refused on purpose -- it needs a hook, and the stock arm of
        // this comparison must install none.
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
// Correlating "what I did on screen" with "what the log says" after the fact is the whole
// point of the exercise, and timestamps alone are ambiguous at 250ms poll granularity. The
// driver writes a one-line label into a marker file before each test case; the observer
// notices the change and stamps it into the log, in-band, between the snapshots it
// separates. Reading a file the observer owns is not a write to, or a hook into, the game.
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

    // Every scan below fires on the marker and is read-only. Ordering rule: the reads of
    // the ENGINE's own state come before the plugin's own bookkeeping (the shadow dump),
    // so a run that reads both gets the engine's view first.

    // The only view of unit state that exists in observe mode, the stock arm of the
    // plugin-vs-stock comparison.
    ScanWorld(g_lastMarker);

    // LogSnapshot below prints the same three arrays, but only when the snapshot CHANGED
    // since the last 250 ms tick. "Did that shift-click do anything?" needs a read AT a
    // named instant, and a change-gated line is silent precisely when the answer is
    // "nothing happened" -- silence indistinguishable from "the observer stopped".
    //
    // All three, because they are three different layers and a symptom does not say which
    // one refused (research/building-groups.md 2, 3): `client` is what the STOCK status
    // row draws, `active` is what the client selected, `sim` is what the simulation holds
    // and what every order applier iterates.
    LogSelectionArrays(g_lastMarker);

    ScCardScan(g_lastMarker);

    // The card and the status strip are the two dialogs a player can click to cancel a
    // queued unit -- the card's slot-9 button sends "cancel the LAST item", the strip's
    // five icons address a SPECIFIC one -- so a run that reads one wants the other too.
    ScStatusScan(g_lastMarker);

    // Which GAME this marker was taken in, before anything that prints a record, so a
    // reader never has to work out which side of a game start a record's line fell on --
    // the epoch it was read under is directly above it.
    ScSessionLogState(g_lastMarker);

    // The console module's marker-driven test aid (a 'conedge-select' label asks the
    // GAME thread to select the first completed own unit on its next frame). A no-op
    // unless the module is installed, which observe never does.
    ScConsoleOnMarker(g_lastMarker);
    ScMarkTraceOnMarker(g_lastMarker);
    ScCursorPostedPoll();

    ScanScreen(g_lastMarker);

    // The composed frame itself, straight out of the screen Bitmap -- the one oracle
    // that sees the columns the presented window discards.
    DumpFrame(g_lastMarker);

    // Storm's own present state -- geometry, the flip clip, the fallback lock pointer
    // and the present region -- read straight out of storm.dll: the instrument that says
    // which buffer->glass present path is live. Off unless %SCPLUGIN_STORM_PRESENT%.
    ScStormPresentLog(g_lastMarker);

    // A marker is the driver saying "look now", so it is also the trigger for the
    // per-unit state dump. Driving it off the marker rather than off a timer is what
    // makes an unattended assertion possible at all -- the test writes a marker, waits
    // for the UNITSTATE line carrying that exact tag, and asserts on it. No polling
    // race, and no extra IPC beyond the file channel that already exists.
    ScFanoutLogUnitStates(g_lastMarker);

    // The ENGINE's own five slots read straight out of CUnit+0x98 beside the plugin's
    // overflow, so an unattended run asserts a queue length from the building's memory
    // rather than from the screen. A no-op when %SCPLUGIN_PRODQ% is off.
    ScProdQueueLogState(g_lastMarker);

    // One line per building in the shadow selection, each carrying that building's own
    // five queue slots. Unlike the line above it does NOT depend on its feature being
    // enabled: the baseline ("with N buildings selected, how many gain an item in a
    // stock game") is taken with this oracle, and an oracle that only exists in the
    // treatment arm proves nothing about the control arm.
    ScProdFanLogState(g_lastMarker);
    // The building's OWN research state -- CUnit+0xC8/0xC9/0xC6/0xCD -- beside the
    // plugin's queue, so an unattended run reads "which upgrade, at which level, with
    // how long left" out of the engine's memory instead of off the status area. A no-op
    // when %SCPLUGIN_UPGQ% is off.
    ScUpgQueueLogState(g_lastMarker);

    // What the QUEUE-OVERFLOW INDICATOR is actually showing, read back out of the live
    // dialog: is its control linked into the child chain, does the engine's own visible
    // bit sit on it, what string does its pszText pointer really hold. Enabled or not,
    // for the same reason the prodfan oracle above is -- "nothing is drawn with the
    // feature off" is half the acceptance criteria, and an oracle that only exists in
    // the treatment arm cannot measure the control arm.
    ScQueueIndLogState(g_lastMarker);
}

// ---------------------------------------------------------------------------
// Active-dialog scan -- READ-ONLY
//
// Dismissing the "StarCraft Tips" dialog by clicking a HARDCODED point (200,261)
// checks neither that a dialog was ever there nor that it went away. With the dialog
// list readable, a suite finds the tips dialog, clicks ITS OWN OK button wherever the
// engine put it, and asserts the dialog is gone (AGENTS.md § "Tips dialog").
//
// The walk is the engine's own: head at SC_VA_DIALOG_LIST, "next" at +0x00, controls
// from +0x42, each with text at +0x14 and bounds at +0x04 -- the layout sc_hudrow
// also reads (sc_addresses.h carries the per-offset evidence). Every read goes through
// SafeRead; nothing here writes, hooks or calls into the game.
//
// One line per CHANGE of the dialog set, not per tick: a menu that sits still logs
// once. %SCPLUGIN_DIALOGS%=0 turns it off.
// ---------------------------------------------------------------------------

static bool g_dialogScan = true;

// Copies a NUL-terminated string out of the game, one byte at a time through
// SafeRead, and sanitises it for the log: dialog text is game data, so a stray
// newline or '|' would corrupt the line a parser is about to read.
static void ReadDlgText(DWORD ptr, char* out, size_t outLen) {
    ScLogCopyText(ptr, out, outLen);
}

// left,top,right,bottom -- four s16 at +0x04 (SC_BINDLG_OFF_BOUNDS).
static void ReadDlgRect(DWORD dlg, int* r) {
    for (int i = 0; i < 4; ++i) {
        unsigned v = 0;
        r[i] = ReadU16(dlg + SC_BINDLG_OFF_BOUNDS + (unsigned)i * 2, &v) ? (int)(short)v : -1;
    }
}

// Appends one formatted fragment; false once the buffer is full.
static bool DlgAppend(char* buf, size_t cap, size_t* used, const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int w = _vsnprintf(buf + *used, cap - *used, fmt, ap);
    va_end(ap);
    if (w < 0 || (size_t)w >= cap - *used) return false;
    *used += (size_t)w;
    return true;
}

static void ScanDialogs(void) {
    if (!g_dialogScan) return;

    // The line carries everything; the CHANGE test runs on a key that leaves out the
    // control TEXT of the in-game status dialogs (Stat*): hit points, supplies and
    // minerals change on nearly every poll, and one line per poll is most of a
    // session's log. Their controls' rects stay in the key, so a child that appears
    // with a selection (an armour icon, a queue slot) still logs a fresh line. Every
    // other dialog keeps its text in the key, because a menu's game-type combo changes
    // text without changing a rect.
    static char prev[2048] = { 0 };
    char line[2048], key[2048];
    size_t used = 0, kused = 0;
    line[0] = key[0] = '\0';

    DWORD dlg = 0;
    int n = 0;
    if (ReadU32(ScRuntimeVa(SC_VA_DIALOG_LIST), &dlg)) {
        while (dlg && n < SC_MAX_DIALOGS_WALK) {
            char name[64];
            DWORD text = 0;
            ReadU32(dlg + SC_BINDLG_OFF_TEXT, &text);
            ReadDlgText(text, name, sizeof(name));
            int r[4];
            ReadDlgRect(dlg, r);

            if (!DlgAppend(line, sizeof(line), &used, "%s dlg='%s' rect=%d,%d,%d,%d",
                           used ? " |" : "", name, r[0], r[1], r[2], r[3])) break;
            DlgAppend(key, sizeof(key), &kused, "%s dlg='%s' rect=%d,%d,%d,%d",
                      kused ? " |" : "", name, r[0], r[1], r[2], r[3]);
            const bool liveText = strncmp(name, "Stat", 4) == 0;

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
                    if (!DlgAppend(line, sizeof(line), &used,
                                   " ctrl='%s' rect=%d,%d,%d,%d type=%u flags=0x%X",
                                   ctext, cr[0], cr[1], cr[2], cr[3], type, flags)) break;
                    DlgAppend(key, sizeof(key), &kused,
                              " ctrl='%s' rect=%d,%d,%d,%d type=%u flags=0x%X",
                              liveText ? "" : ctext, cr[0], cr[1], cr[2], cr[3], type, flags);
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

    if (strcmp(key, prev) == 0) return;
    lstrcpynA(prev, key, (int)sizeof(prev));
    ScLog("DIALOGS n=%d%s%s", n, n ? " " : "", line);
}

static DWORD GetPollMs(void) {
    return (DWORD)ScEnvInt("SCPLUGIN_POLL_MS", 250, 20, 5000);
}

static ScMode g_mode = SC_MODE_OBSERVE;

static bool GetWorldScan(void) {
    return ScEnvOptIn("SCPLUGIN_WORLDSCAN");
}

// ON by default, unlike the world scan: one line per CHANGE of the dialog set is a
// handful of lines per run, and every suite's tips-dialog dismissal depends on it.
static bool GetDialogScan(void) {
    return ScEnvFlag("SCPLUGIN_DIALOGS", true);
}

// OFF by default, same shape and reason as the world scan.
static bool GetCardScan(void) {
    return ScEnvOptIn("SCPLUGIN_CARDSCAN");
}

// OFF by default, same shape and reason as the world scan.
static bool GetScreenScan(void) {
    return ScEnvOptIn("SCPLUGIN_SCREENSCAN");
}

static DWORD WINAPI ObserverThread(LPVOID) {
    const DWORD pollMs = GetPollMs();
    g_worldScan = GetWorldScan();
    g_screenScan = GetScreenScan();
    g_frameDump = GetFrameDump();
    g_dialogScan = GetDialogScan();
    // The read-only command-card scan must exist in observe mode too, because "the
    // card the stock game draws" is half of every comparison.
    ScCardInit(ScEngineModuleBase(), GetCardScan());
    ResolveMarkerPath();
    ScLog("OBSERVER start pollMs=%u mode=%s%s", (unsigned)pollMs, ScModeName(g_mode),
          g_mode == SC_MODE_OBSERVE ? " (read-only; no writes to game memory)" : "");
    ScLog("OBSERVER marker file: %s", g_markerPath);
    ScLog("OBSERVER worldScan=%d (%%SCPLUGIN_WORLDSCAN%%; read-only walk of the engine's "
          "own per-player unit lists, installs no hook and works in observe mode)",
          g_worldScan ? 1 : 0);
    ScLog("OBSERVER cardScan=%d (%%SCPLUGIN_CARDSCAN%%; read-only walk of the command-card "
          "dialog 0x0068C148 AND the status pane's queue strip 0x0068C1F0, installs no "
          "hook and works in observe mode)",
          ScCardEnabled() ? 1 : 0);
    ScLog("OBSERVER screenScan=%d (%%SCPLUGIN_SCREENSCAN%%; read-only read-back of the screen "
          "Bitmap 0x006CEFF0, the 8 graphic layers 0x006CEF50 and the scroll clamp, installs "
          "no hook and works in observe mode)",
          g_screenScan ? 1 : 0);
    ScLog("OBSERVER frameDump=%d (%%SCPLUGIN_FRAMEDUMP%%; read-only per-marker copy of the "
          "composed frame out of the screen Bitmap's own buffer, installs no hook and works "
          "in observe mode)%s%s",
          g_frameDump ? 1 : 0,
          g_frameDump ? " dir=" : "", g_frameDump ? g_frameDumpDir : "");
    // Which ARM this run is, printed next to the read-back's own switch because every
    // SCREEN line below is only interpretable against it -- 800x480 is the result in
    // one arm and a defect in the other.
    ScLog("OBSERVER widescreen=%d (%%SCPLUGIN_WIDESCREEN%%; %s)",
          ScScreenActive() ? 1 : 0,
          ScScreenActive() ? "the screen geometry HAS been repatched"
                           : "stock geometry, nothing repatched");

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

static void LogAttachBanner(void) {
    HMODULE exeMod = GetModuleHandleA(NULL);
    ScEngineSetModuleBase((BYTE*)exeMod);

    char exePath[MAX_PATH] = {0};
    GetModuleFileNameA(exeMod, exePath, MAX_PATH);

    char dllPath[MAX_PATH] = {0};
    HMODULE self = NULL;
    GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                       GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       (LPCSTR)&LogAttachBanner, &self);
    if (self) GetModuleFileNameA(self, dllPath, MAX_PATH);

    LONG delta = (LONG)((DWORD_PTR)ScEngineModuleBase() - SC_PREFERRED_IMAGE_BASE);

    ScLog("========================================================");
    ScLog("ATTACH pid=%u tid=%u", (unsigned)GetCurrentProcessId(),
          (unsigned)GetCurrentThreadId());
    // FIRST line of the banner, so every log, transcript and frame this run produces can
    // name the build behind it. "<short sha>[+dirty] SRC=<12 hex over tools/plugin/src +
    // build.ps1>": the sha answers "which commit", the digest answers "which source
    // bytes", and the digest is the half that still means something when +dirty says the
    // sha is a lie. UNSTAMPED means this DLL did not come from build.ps1 at all.
    ScLog("  build         : %s", ScBuildStampShort());
    ScLog("  host exe      : %s", exePath);
    ScLog("  plugin dll    : %s", dllPath);
    // Where WE landed, against the base the FILE asks for. build.ps1 pins that base to
    // make the build byte-reproducible, and whether the loader honours it is a fact about
    // this process, not about the flag.
    //
    // READ FROM THE FILE, NOT FROM THE MAPPED IMAGE: the Windows loader REWRITES
    // OptionalHeader.ImageBase in the mapped header to the address it actually used.
    // Measured -- the file on disk holds 0x71000000, the mapped header read 0x717D0000,
    // the module loaded at 0x717D0000 -- so a check reading the mapped header compares
    // the load address against itself and reports "the pinned base took" for a module the
    // loader has just relocated. An instrument whose reading moves with its own input
    // cannot fail (AGENTS.md § "Oracles: what counts as a read-back").
    if (self && dllPath[0]) {
        DWORD loadedAt = (DWORD)(DWORD_PTR)self;
        DWORD preferred = 0;
        HANDLE fh = CreateFileA(dllPath, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (fh != INVALID_HANDLE_VALUE) {
            DWORD got = 0;
            LONG e_lfanew = 0;
            if (SetFilePointer(fh, 0x3C, NULL, FILE_BEGIN) != INVALID_SET_FILE_POINTER &&
                ReadFile(fh, &e_lfanew, sizeof(e_lfanew), &got, NULL) && got == sizeof(e_lfanew) &&
                e_lfanew > 0 && e_lfanew < 0x1000 &&
                // PE32: optional header at e_lfanew+24, ImageBase +28 into it.
                SetFilePointer(fh, e_lfanew + 24 + 28, NULL, FILE_BEGIN) != INVALID_SET_FILE_POINTER &&
                ReadFile(fh, &preferred, sizeof(preferred), &got, NULL) && got == sizeof(preferred)) {
                /* preferred is set */
            } else {
                preferred = 0;
            }
            CloseHandle(fh);
        }
        if (preferred) {
            ScLog("  plugin base   : 0x%08X  (the FILE asks for 0x%08X -- %s)",
                  (unsigned)loadedAt, (unsigned)preferred,
                  loadedAt == preferred
                      ? "loaded where it asked"
                      : "RELOCATED by the loader; that range was taken in this process");
        } else {
            ScLog("  plugin base   : 0x%08X  (could not read the file's own PE header -- "
                  "cannot say whether it was relocated)", (unsigned)loadedAt);
        }
    }
    ScLog("  module base   : 0x%08X", (unsigned)(DWORD_PTR)ScEngineModuleBase());
    ScLog("  preferred base: 0x%08X", (unsigned)SC_PREFERRED_IMAGE_BASE);
    ScLog("  reloc delta   : %s0x%08X  => static addresses are %s",
          delta < 0 ? "-" : "+", (unsigned)(delta < 0 ? -delta : delta),
          delta == 0 ? "USABLE VERBATIM" : "SHIFTED (rebased by the plugin)");

    // Read a couple of bytes at the image base as a sanity check that we are
    // reading the mapped image at all ('MZ' == 0x5A4D).
    WORD mz = 0;
    if (ScSafeRead(ScEngineModuleBase(), &mz, 2)) {
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
        g_mode = ScModeResolve();
        LogAttachBanner();
        // FIRST of everything that writes: the widescreen patch set rewrites the
        // operands of functions that run during the game's own startup, so it is only
        // correct if it lands before the video init. It refuses (and changes nothing)
        // if it finds the framebuffer already allocated, which is what happens on the
        // default late injection.
        ScScreenInstall(ScEngineModuleBase(), g_mode);
        // The game-session epoch, in BEFORE every module that keeps records: each of
        // those asks it "which game is this?" at the top of every entry point, so it
        // has to exist -- and be at its starting value -- before any of them can hold
        // anything. Spliced only outside observe mode, like everything else that
        // writes game memory; in observe the epoch stays 1, which is correct because
        // no module holds cross-frame state there.
        ScSessionInstall(ScEngineModuleBase(), g_mode != SC_MODE_OBSERVE);
        // The console move + click-route trace both write to dialog records on the
        // game thread, so observe -- the whole plugin's off switch -- ignores them
        // like every other writer.
        {
            bool consoleTrace = ScConsoleTraceWanted();
            if (g_mode == SC_MODE_OBSERVE && consoleTrace) {
                ScLog("CONSOLE: %%SCPLUGIN_CONSOLE_TRACE%% set but the mode is observe "
                      "-- IGNORED. Observe writes nothing to game memory.");
                consoleTrace = false;
            }
            ScConsoleInstall(ScEngineModuleBase(), g_mode != SC_MODE_OBSERVE, consoleTrace);
        }
        ScMarkTraceInstall(ScEngineModuleBase(), g_mode != SC_MODE_OBSERVE);
        ScCursorPostedInstall(ScEngineModuleBase(), g_mode != SC_MODE_OBSERVE);
        // The storm-side buffer->glass present. PROBE is read-only and runs in any
        // mode; WIDEN writes storm's geometry and is gated out of observe like every
        // other writer (the module enforces this itself).
        ScStormPresentInstall(ScEngineModuleBase(), g_mode != SC_MODE_OBSERVE);
        ScFanoutInstall(ScEngineModuleBase(), g_mode);
        // The prodfan oracle needs the module base in EVERY mode, because the stock arm
        // of this feature's comparison runs in observe and is measured with it. The
        // FEATURE half is gated like every other writer: observe writes nothing to game
        // memory and emits no command, whatever else the environment asks for.
        {
            bool prodfanWanted = ScProdFanEnabled();
            if (g_mode == SC_MODE_OBSERVE && prodfanWanted) {
                ScLog("PRODFAN: %%SCPLUGIN_PRODFAN%% is set but the mode is observe -- "
                      "the fan-out is IGNORED. The read-only oracle still runs.");
            }
            ScProdFanInit(ScEngineModuleBase(), prodfanWanted && g_mode != SC_MODE_OBSERVE);
            // The button-condition detour goes in under its own thread suspension, after
            // the fan-out's splice has been made and resumed. Without the button the
            // player cannot issue the command at all, so this is the half of the feature
            // that has to succeed for the other half to mean anything -- and a failure
            // here turns the whole feature off rather than leaving it half-armed.
            if (ScProdFanEnabled()) ScProdFanInstall();
        }
        // Gated on %SCPLUGIN_PRODQ% AND on not being in observe mode: observe is the
        // whole plugin's off switch and must stay a byte-for-byte read-only observer,
        // whatever else is set in the environment.
        if (g_mode == SC_MODE_OBSERVE) {
            // Observe never reaches ScFanoutInstall, so the indicator is initialised
            // here instead -- DISABLED, but with a module base, so its read-only oracle
            // still answers on the marker channel. "Nothing is drawn with the feature
            // off" is half of what a run has to show, and an oracle that goes silent in
            // the control arm cannot show it
            // (AGENTS.md § "Oracles: absence and defect-era checks").
            ScQueueIndInit(ScEngineModuleBase(), false);
            if (ScQueueIndEnabled()) {
                ScLog("QIND: %%SCPLUGIN_QUEUEIND%% is set but the mode is observe -- "
                      "IGNORED. Observe writes nothing to game memory.");
            }
            if (ScProdQueueEnabled()) {
                ScLog("PRODQ: %%SCPLUGIN_PRODQ%% is set but the mode is observe -- "
                      "IGNORED. Observe writes nothing to game memory.");
            }
            // Same gate and same reason.
            if (ScUpgQueueEnabled()) {
                ScLog("UPGQ: %%SCPLUGIN_UPGQ%% is set but the mode is observe -- "
                      "IGNORED. Observe writes nothing to game memory.");
            }
        } else {
            ScProdQueueInstall(ScEngineModuleBase());
            ScUpgQueueInstall(ScEngineModuleBase());
        }
        // The observer runs on its own thread; DllMain itself does nothing but
        // start it, so we never hold the loader lock while polling.
        g_observer = CreateThread(NULL, 0, ObserverThread, NULL, 0, NULL);
        if (!g_observer) ScLog("ERROR CreateThread failed gle=%u",
                               (unsigned)GetLastError());
    } else if (reason == DLL_PROCESS_DETACH) {
        InterlockedExchange(&g_stop, 1);

        // lpReserved == NULL means FreeLibrary: the observer thread is still running and
        // this DLL's code is about to be unmapped underneath it, so it has to be joined
        // before the log handle and the lock are destroyed. The thread only calls file,
        // memory and Sleep APIs -- never LoadLibrary or FreeLibrary -- so it cannot be
        // waiting on the loader lock DllMain holds, and this bounded wait cannot deadlock.
        //
        // lpReserved != NULL means the process is exiting: Windows has already terminated
        // every other thread, so there is nothing to join, and the log lock may be
        // permanently owned by one of those terminated threads.
        bool joined = true;
        if (lpReserved != NULL) ScLogSetTryLock();
        ScFanoutLogStats();   // the run's counters, on both detach paths
        ScProdQueueLogStats();
        ScProdFanLogStats();
        ScUpgQueueLogStats();
        ScScreenLogStats();
        ScConsoleLogStats();
        ScStormPresentLogStats();
        ScSessionLogState("detach");
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
            // The prodfan detour holds nothing, so its position is free; here the card
            // is back to stock before the fan-out's own hooks leave.
            ScProdFanRemove();
            // Every item the upgrade queue holds is unpaid, so it has nothing to give
            // back and its position is free too. Before the fan-out's, so the whole
            // splice comes out newest-first.
            ScUpgQueueRemove();
            ScFanoutRemove();
            // Console bounds restored and interacts unwrapped before the widescreen
            // geometry (which the move's +160 only makes sense on) comes out below.
            ScConsoleRemove();
            ScMarkTraceRemove();
            ScCursorPostedRemove();
            // Storm present: PROBE has nothing to restore, WIDEN restores storm's
            // geometry. Comes out before the exe geometry below.
            ScStormPresentRemove();
            // The geometry patches are the outermost change, so they leave after every
            // detour that might still be running against them.
            ScScreenRemove();
            // The epoch's own splice comes out LAST, after every module that reads it:
            // a module still running its SessionSync while the counter's writer was
            // already gone would be asking a question nothing can answer any more.
            ScSessionRemove();
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
