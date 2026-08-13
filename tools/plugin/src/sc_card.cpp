// sc_card.cpp -- read the command card out of the running process. See sc_card.h.

#include "sc_card.h"

#include <stdio.h>
#include <string.h>

#include "sc_log.h"
#include "sc_queueind.h"   // ScQueueIndRingGen -- the phantom window's seqlock (task 066)

static BYTE*        g_base    = NULL;
static bool         g_enabled = false;
static ScCardReadFn g_read    = NULL;

static DWORD Rt(DWORD staticVa) {
    return (DWORD)(DWORD_PTR)(g_base + (staticVa - SC_PREFERRED_IMAGE_BASE));
}

static bool Rd(DWORD addr, void* out, size_t n) {
    if (!g_read || !addr) return false;
    return g_read(addr, out, n);
}

static bool RdU8(DWORD addr, BYTE* out)   { return Rd(addr, out, 1); }
static bool RdU16(DWORD addr, WORD* out)  { return Rd(addr, out, 2); }
static bool RdU32(DWORD addr, DWORD* out) { return Rd(addr, out, 4); }

// ---------------------------------------------------------------------------
// The walk
// ---------------------------------------------------------------------------

// Reproduces the layout function's own child walk (0x004591D0):
//
//     root = cardDialog;
//     if (*(s16*)(root + 0x22) != 0) root = *(BinDlg**)(root + 0x32);   // climb to parent
//     ctrl = *(BinDlg**)(root + 0x42);                                  // first child
//     while (ctrl->index != 1) ctrl = ctrl->next;                       // find slot 1
//     ... slots are the children with 1 <= index < 10 ...
//
// with two differences, both because this is an observer and not the engine: the
// walk is bounded (never trust a game list read from another thread to terminate)
// and it collects rather than assigns.
int ScCardSnapshot(ScCardHeader* hdr, ScCardSlot* out, int max) {
    if (!hdr) return 0;
    memset(hdr, 0, sizeof(*hdr));

    if (!RdU32(Rt(SC_VA_CARD_DIALOG), &hdr->dialog) || hdr->dialog == 0) return 0;
    hdr->ok = true;

    RdU16(Rt(SC_VA_CARD_ID), &hdr->cardId);
    RdU16(Rt(SC_VA_CARD_OVERRIDE_SEL), &hdr->overrideSel);
    RdU16(Rt(SC_VA_CARD_OVERRIDE_SUB), &hdr->overrideSub);
    RdU32(Rt(SC_VA_CARD_REFUSE_REASON), &hdr->refuseReason);

    if (RdU32(Rt(SC_VA_ACTIVE_PORTRAIT_UNIT), &hdr->portrait) && hdr->portrait) {
        RdU16(hdr->portrait + SC_CUNIT_OFF_UNIT_ID, &hdr->portraitType);
        RdU16(hdr->portrait + SC_CUNIT_OFF_BUTTONSET, &hdr->portraitSet);
        RdU16(hdr->portrait + SC_CUNIT_OFF_ENERGY, &hdr->portraitEnergy);
        RdU8(hdr->portrait + SC_CUNIT_OFF_PLAYER, &hdr->portraitOwner);
    }

    // The buttonset the card id resolves to, straight out of the table. Bounded by
    // the table's own length, which is read off the binary (sc_addresses.h).
    if (hdr->cardId < SC_BUTTONSET_COUNT) {
        DWORD e = Rt(SC_VA_BUTTONSET_TABLE) + (DWORD)hdr->cardId * SC_BUTTONSET_STRIDE;
        RdU16(e + SC_BUTTONSET_OFF_N, &hdr->setCount);
        RdU32(e + SC_BUTTONSET_OFF_PTR, &hdr->setButtons);
    }

    // Climb to the dialog record the children hang off, exactly as the layout does.
    hdr->root = hdr->dialog;
    WORD type = 0;
    if (RdU16(hdr->dialog + SC_BINDLG_OFF_TYPE, &type) && (short)type != 0) {
        DWORD parent = 0;
        if (RdU32(hdr->dialog + SC_BINDLG_OFF_PARENT, &parent) && parent) hdr->root = parent;
    }

    Rd(hdr->root + SC_BINDLG_OFF_BOUNDS, hdr->rootRect, sizeof(hdr->rootRect));

    DWORD ctrl = 0;
    if (!RdU32(hdr->root + SC_BINDLG_OFF_FIRST_CHILD, &ctrl)) return 0;

    int found = 0;
    // 64 is a bound, not a count: the statbtn dialog holds more controls than the
    // nine slots (the tooltip/label controls sit past index 9), and a torn read of
    // `next` must not spin.
    for (int guard = 0; ctrl && guard < 64; ++guard) {
        WORD  idxW = 0;
        DWORD next = 0;
        if (!RdU16(ctrl + SC_BINDLG_OFF_INDEX, &idxW)) break;
        int idx = (short)idxW;

        if (idx >= SC_CARD_FIRST_CONTROL && idx <= SC_CARD_LAST_CONTROL && found < max && out) {
            ScCardSlot* s = &out[found];
            memset(s, 0, sizeof(*s));
            s->control = ctrl;
            s->index   = idx;
            RdU32(ctrl + SC_BINDLG_OFF_FLAGS, &s->flags);
            s->visible  = (s->flags & SC_CTRL_FLAG_VISIBLE) != 0;
            s->disabled = (s->flags & SC_CTRL_FLAG_DISABLED) != 0;
            RdU16(ctrl + SC_BINDLG_OFF_GRAPHIC, &s->graphic);
            RdU32(ctrl + SC_BINDLG_OFF_USER, &s->button);
            Rd(ctrl + SC_BINDLG_OFF_BOUNDS, s->rect, sizeof(s->rect));

            if (s->button) {
                // All eight fields or none: a partially read Button is worse than an
                // absent one, because it reads as a named ability with a wrong id.
                s->buttonOk =
                    RdU16(s->button + SC_BUTTON_OFF_SLOT,       &s->bSlot) &&
                    RdU16(s->button + SC_BUTTON_OFF_ICON,       &s->bIcon) &&
                    RdU32(s->button + SC_BUTTON_OFF_COND,       &s->bCond) &&
                    RdU32(s->button + SC_BUTTON_OFF_ACTION,     &s->bAction) &&
                    RdU16(s->button + SC_BUTTON_OFF_COND_PARAM, &s->bCondParam) &&
                    RdU16(s->button + SC_BUTTON_OFF_ACT_PARAM,  &s->bActParam) &&
                    RdU16(s->button + SC_BUTTON_OFF_NAME_STR,   &s->bNameStr) &&
                    RdU16(s->button + SC_BUTTON_OFF_DIS_STR,    &s->bDisStr);
            }

            if (s->visible) {
                ++hdr->shown;
                if (s->disabled) ++hdr->greyed;
            }
            ++found;
        }

        if (!RdU32(ctrl + SC_BINDLG_OFF_NEXT, &next)) break;
        ctrl = next;
    }

    hdr->slots = found;
    return found;
}

// ---------------------------------------------------------------------------
// The status pane's production-queue strip (task 028)
//
// Reproduces queueLayout's own walk (0x004268D0), quoted in sc_addresses.h:
//
//     root = statdataDialog;
//     if (*(s16*)(root + 0x22) != 0) root = *(BinDlg**)(root + 0x32);
//     for (ctrl = root->firstChild; ctrl; ctrl = ctrl->next) if (ctrl->index == 2) break;
//     for (k = 0; ctrl && k < 5; ++k, ctrl = ctrl->next) { ... buildQueue[(head + k) % 5] ... }
//
// The engine takes the DISPLAY INDEX from the walk position and the click payload
// from `index - 2` (statusCtrlActivate 0x004573A0). Those are two different numbers
// that the engine assumes are equal, so both are reported and the caller asserts it.
// ---------------------------------------------------------------------------

int ScStatusSnapshot(ScStatusHeader* hdr, ScStatusSlot* out, int max) {
    if (!hdr) return 0;
    memset(hdr, 0, sizeof(*hdr));

    if (!RdU32(Rt(SC_VA_STATDATA_DIALOG), &hdr->dialog) || hdr->dialog == 0) return 0;
    hdr->ok = true;

    hdr->root = hdr->dialog;
    WORD type = 0;
    if (RdU16(hdr->dialog + SC_BINDLG_OFF_TYPE, &type) && (short)type != 0) {
        DWORD parent = 0;
        if (RdU32(hdr->dialog + SC_BINDLG_OFF_PARENT, &parent) && parent) hdr->root = parent;
    }
    Rd(hdr->root + SC_BINDLG_OFF_BOUNDS, hdr->rootRect, sizeof(hdr->rootRect));

    // The queue the strip is DRAWING is the portrait unit's, not the selection's --
    // 0x004268D0 reads DAT_00597248 for every one of its five slots. Reading the same
    // global is what makes "icon k shows type t" checkable against the building's ring.
    if (RdU32(Rt(SC_VA_ACTIVE_PORTRAIT_UNIT), &hdr->portrait) && hdr->portrait) {
        RdU16(hdr->portrait + SC_CUNIT_OFF_UNIT_ID, &hdr->portraitType);
        RdU8(hdr->portrait + SC_CUNIT_OFF_PLAYER, &hdr->portraitOwner);
        // COHERENT against the phantom bracket (task 066, sc_queueind.h): this walk runs
        // on the observer thread, and the game thread makes owned ring slots non-empty
        // for the length of each queueLayout call. A qtype read mid-window would report
        // a phantom item as the engine's, which is exactly what the suites assert
        // against ("the ring slot behind it is EMPTY -- the item is the plugin's").
        bool ok = false;
        hdr->ringStable = false;
        for (int attempt = 0; attempt < 32 && !hdr->ringStable; ++attempt) {
            unsigned g1 = ScQueueIndRingGen();
            if (g1 & 1) continue;
            ok = RdU8(hdr->portrait + SC_CUNIT_OFF_BUILD_QUEUE_SLOT, &hdr->head);
            for (int i = 0; i < SC_BUILD_QUEUE_SLOTS; ++i) {
                ok = RdU16(hdr->portrait + SC_CUNIT_OFF_BUILD_QUEUE + (DWORD)i * 2,
                           &hdr->queue[i]) && ok;
            }
            if (ScQueueIndRingGen() == g1) hdr->ringStable = true;
        }
        hdr->queueOk = ok;
    }

    DWORD ctrl = 0;
    if (!RdU32(hdr->root + SC_BINDLG_OFF_FIRST_CHILD, &ctrl)) return 0;

    // Find the strip's first icon the way the layout does -- by index, not by position.
    // Bounded because this runs on the observer thread against a list the game thread
    // owns; a torn `next` must end the walk, not spin it.
    DWORD first = 0;
    for (int guard = 0; ctrl && guard < SC_MAX_CTRLS_WALK; ++guard) {
        WORD idxW = 0;
        if (!RdU16(ctrl + SC_BINDLG_OFF_INDEX, &idxW)) break;
        if ((short)idxW == SC_STATQ_FIRST_CONTROL) { first = ctrl; break; }
        DWORD next = 0;
        if (!RdU32(ctrl + SC_BINDLG_OFF_NEXT, &next)) break;
        ctrl = next;
    }
    if (!first) return 0;

    int found = 0;
    ctrl = first;
    for (int k = 0; ctrl && k < SC_STATQ_SLOTS; ++k) {
        if (found >= max || !out) break;
        ScStatusSlot* s = &out[found];
        memset(s, 0, sizeof(*s));
        s->display = k;
        s->control = ctrl;

        WORD idxW = 0;
        s->index = RdU16(ctrl + SC_BINDLG_OFF_INDEX, &idxW) ? (short)idxW : -1;
        RdU32(ctrl + SC_BINDLG_OFF_FLAGS, &s->flags);
        s->visible  = (s->flags & SC_CTRL_FLAG_VISIBLE) != 0;
        s->disabled = (s->flags & SC_CTRL_FLAG_DISABLED) != 0;
        RdU16(ctrl + SC_BINDLG_OFF_GRAPHIC, &s->graphic);
        RdU32(ctrl + SC_BINDLG_OFF_USER, &s->user);
        Rd(ctrl + SC_BINDLG_OFF_BOUNDS, s->rect, sizeof(s->rect));

        if (s->user) {
            // All three fields or none, same rule as the card's Button record: a
            // half-read statUser reads as an icon drawing a wrong unit type.
            s->userOk = RdU16(s->user + SC_STATUSER_OFF_ICON, &s->uIcon) &&
                        RdU16(s->user + SC_STATUSER_OFF_MODE, &s->uMode) &&
                        RdU16(s->user + SC_STATUSER_OFF_TYPE, &s->uType);
        }

        // The building's own slot for this display index -- the engine's arithmetic,
        // (head + k) % 5, so the icon and the ring can be compared without the caller
        // having to redo it.
        s->queueType = SC_BUILD_QUEUE_EMPTY;
        if (hdr->queueOk) {
            s->queueType = hdr->queue[((unsigned)hdr->head + (unsigned)k) % SC_BUILD_QUEUE_SLOTS];
        }

        if (s->visible) {
            ++hdr->shown;
            if (!s->disabled) ++hdr->clickable;
        }
        ++found;

        DWORD next = 0;
        if (!RdU32(ctrl + SC_BINDLG_OFF_NEXT, &next)) break;
        ctrl = next;
    }

    hdr->slots = found;
    return found;
}

void ScStatusScan(const char* tag) {
    if (!g_enabled) return;

    ScStatusHeader hdr;
    ScStatusSlot   slots[SC_STATQ_SLOTS];
    int n = ScStatusSnapshot(&hdr, slots, SC_STATQ_SLOTS);

    const char* t = tag ? tag : "-";
    if (!hdr.ok) {
        ScLog("STATQ [%s] dialog=0 (no status pane in this process state)", t);
        return;
    }

    char eng[96];
    int used = 0;
    eng[0] = '\0';
    for (int i = 0; i < SC_BUILD_QUEUE_SLOTS && used + 8 < (int)sizeof(eng); ++i) {
        used += _snprintf(eng + used, sizeof(eng) - used, "%s0x%03X",
                          i ? "," : "", hdr.queueOk ? (unsigned)hdr.queue[i] : 0xFFFu);
    }

    ScLog("STATQ [%s] dialog=0x%08X root=0x%08X rootrect=(%d,%d,%d,%d) portrait=0x%08X "
          "ptype=0x%03X powner=%u head=%u queueOk=%d ringStable=%d engine=[%s]",
          t, (unsigned)hdr.dialog, (unsigned)hdr.root,
          hdr.rootRect[0], hdr.rootRect[1], hdr.rootRect[2], hdr.rootRect[3],
          (unsigned)hdr.portrait, (unsigned)hdr.portraitType, (unsigned)hdr.portraitOwner,
          (unsigned)hdr.head, hdr.queueOk ? 1 : 0, hdr.ringStable ? 1 : 0, eng);

    for (int i = 0; i < n; ++i) {
        const ScStatusSlot* s = &slots[i];
        const char* state = !s->visible ? "hidden" : (s->disabled ? "GREYED" : "enabled");
        ScLog("STATQ [%s] disp=%d %-7s idx=%d ctrl=0x%08X flags=0x%08X graphic=0x%04X "
              "rect=(%d,%d,%d,%d) user=0x%08X uicon=0x%04X umode=%u utype=0x%03X "
              "qtype=0x%03X",
              t, s->display, state, s->index, (unsigned)s->control, (unsigned)s->flags,
              (unsigned)s->graphic, s->rect[0], s->rect[1], s->rect[2], s->rect[3],
              (unsigned)s->user,
              s->userOk ? (unsigned)s->uIcon : 0xFFFFu,
              s->userOk ? (unsigned)s->uMode : 0xFFFFu,
              s->userOk ? (unsigned)s->uType : 0xFFFu,
              (unsigned)s->queueType);
    }

    // Written LAST and unconditionally, like the card's: a reader waits for this line,
    // and "the strip is up but nothing is clickable" has to be a positive answer rather
    // than a missing one (AGENTS.md, absence assertions).
    ScLog("STATQ [%s] slots=%d shown=%d clickable=%d", t, hdr.slots, hdr.shown, hdr.clickable);
}

// ---------------------------------------------------------------------------
// The tech state behind the buttons
// ---------------------------------------------------------------------------

bool ScCardReadTechState(int player, ScCardTechState* out) {
    if (!out) return false;
    memset(out, 0, sizeof(*out));
    out->player = player;
    // Fail closed on a player index the arrays do not have: 12 slots, and a wrong one
    // would read a neighbouring global and report a tech nobody has.
    if (player < 0 || player >= 12) return false;

    bool ok = true;
    for (int t = 0; t < SC_TECH_COUNT_VANILLA; ++t) {
        DWORD off = (DWORD)player * SC_TECH_STRIDE_VANILLA + (DWORD)t;
        ok = RdU8(Rt(SC_VA_TECH_AVAILABLE)  + off, &out->available[t])  && ok;
        ok = RdU8(Rt(SC_VA_TECH_RESEARCHED) + off, &out->researched[t]) && ok;
    }
    for (int t = 0; t < SC_TECH_COUNT_BW; ++t) {
        DWORD off = (DWORD)player * SC_TECH_STRIDE_BW + (DWORD)t;
        ok = RdU8(Rt(SC_VA_TECH_AVAILABLE_BW)  + off,
                  &out->available[SC_TECH_COUNT_VANILLA + t])  && ok;
        ok = RdU8(Rt(SC_VA_TECH_RESEARCHED_BW) + off,
                  &out->researched[SC_TECH_COUNT_VANILLA + t]) && ok;
    }
    out->ok = ok;
    return ok;
}

// "10 11" rather than 44 bytes: the question is always "which techs", and a list of
// ids can be compared against a fixture's own --tech-researched argument by eye.
static void FormatTechList(const BYTE* bits, char* out, size_t outLen) {
    size_t n = 0;
    out[0] = '\0';
    for (int t = 0; t < 44; ++t) {
        if (!bits[t]) continue;
        char tmp[8];
        int k = _snprintf(tmp, sizeof(tmp), n ? " %d" : "%d", t);
        if (k <= 0 || n + (size_t)k + 1 >= outLen) { lstrcpynA(out + n, "...", (int)(outLen - n)); return; }
        memcpy(out + n, tmp, (size_t)k);
        n += (size_t)k;
        out[n] = '\0';
    }
    if (n == 0) lstrcpynA(out, "(none)", (int)outLen);
}

// ---------------------------------------------------------------------------
// Plumbing
// ---------------------------------------------------------------------------

// The plugin's own reader. Declared here rather than shared from scplugin.cpp so
// this translation unit links into hooktest without dragging the observer in.
static bool DefaultRead(DWORD addr, void* out, size_t n) {
    const void* p = (const void*)(DWORD_PTR)addr;
    MEMORY_BASIC_INFORMATION mbi;
    if (VirtualQuery(p, &mbi, sizeof(mbi)) != sizeof(mbi)) return false;
    if (mbi.State != MEM_COMMIT) return false;
    if (mbi.Protect & PAGE_GUARD) return false;

    const DWORD readable = PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY |
                           PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE |
                           PAGE_EXECUTE_WRITECOPY;
    if ((mbi.Protect & readable) == 0) return false;

    const BYTE* start  = (const BYTE*)p;
    const BYTE* regEnd = (const BYTE*)mbi.BaseAddress + mbi.RegionSize;
    if (start < (const BYTE*)mbi.BaseAddress) return false;
    if (start + n > regEnd) return false;

    memcpy(out, p, n);
    return true;
}

void ScCardInit(BYTE* moduleBase, bool enabled) {
    g_base    = moduleBase;
    g_enabled = enabled;
    g_read    = DefaultRead;
}

bool ScCardEnabled(void) { return g_enabled; }

void ScCardTestBegin(BYTE* fakeModuleBase, ScCardReadFn reader) {
    g_base    = fakeModuleBase;
    g_read    = reader;
    g_enabled = true;
}

void ScCardTestEnd(void) {
    g_base    = NULL;
    g_read    = NULL;
    g_enabled = false;
}

void ScCardScan(const char* tag) {
    if (!g_enabled) return;

    ScCardHeader hdr;
    ScCardSlot   slots[SC_CARD_SLOTS];
    int n = ScCardSnapshot(&hdr, slots, SC_CARD_SLOTS);

    const char* t = tag ? tag : "-";
    if (!hdr.ok) {
        ScLog("CARD [%s] dialog=0 (no command card in this process state)", t);
        return;
    }

    ScLog("CARD [%s] dialog=0x%08X root=0x%08X cardId=%u ovrSel=%u ovrSub=%u "
          "portrait=0x%08X ptype=0x%03X pset=%u penergy=%u powner=%u "
          "set=(n=%u buttons=0x%08X) reason=%u rootrect=(%d,%d,%d,%d)",
          t, (unsigned)hdr.dialog, (unsigned)hdr.root, (unsigned)hdr.cardId,
          (unsigned)hdr.overrideSel, (unsigned)hdr.overrideSub,
          (unsigned)hdr.portrait, (unsigned)hdr.portraitType, (unsigned)hdr.portraitSet,
          (unsigned)hdr.portraitEnergy, (unsigned)hdr.portraitOwner,
          (unsigned)hdr.setCount, (unsigned)hdr.setButtons, (unsigned)hdr.refuseReason,
          hdr.rootRect[0], hdr.rootRect[1], hdr.rootRect[2], hdr.rootRect[3]);

    for (int i = 0; i < n; ++i) {
        const ScCardSlot* s = &slots[i];
        // state= is deliberately one word: it is the thing every reader of this log
        // is looking for, and "flags=0x0000000B" is not it.
        const char* state = !s->visible ? "hidden" : (s->disabled ? "GREYED" : "enabled");
        if (s->buttonOk) {
            ScLog("CARD [%s] slot=%d %-7s ctrl=0x%08X flags=0x%08X icon=0x%04X "
                  "rect=(%d,%d,%d,%d) button=0x%08X bslot=%u bicon=0x%04X "
                  "cond=0x%08X act=0x%08X cparam=%u aparam=%u name=0x%04X dis=0x%04X",
                  t, s->index, state, (unsigned)s->control, (unsigned)s->flags,
                  (unsigned)s->graphic,
                  s->rect[0], s->rect[1], s->rect[2], s->rect[3],
                  (unsigned)s->button, (unsigned)s->bSlot,
                  (unsigned)s->bIcon, (unsigned)s->bCond, (unsigned)s->bAction,
                  (unsigned)s->bCondParam, (unsigned)s->bActParam,
                  (unsigned)s->bNameStr, (unsigned)s->bDisStr);
        } else {
            ScLog("CARD [%s] slot=%d %-7s ctrl=0x%08X flags=0x%08X icon=0x%04X "
                  "rect=(%d,%d,%d,%d) button=0x%08X (no button record)",
                  t, s->index, state, (unsigned)s->control, (unsigned)s->flags,
                  (unsigned)s->graphic,
                  s->rect[0], s->rect[1], s->rect[2], s->rect[3],
                  (unsigned)s->button);
        }
    }

    // The tech state of whoever owns the portrait unit, on the same marker. Without it
    // "GREYED" is a symptom; with it, it is a diagnosis.
    ScCardTechState tech;
    if (hdr.portrait && ScCardReadTechState((int)hdr.portraitOwner, &tech)) {
        char av[256], re[256];
        FormatTechList(tech.available, av, sizeof(av));
        FormatTechList(tech.researched, re, sizeof(re));
        ScLog("CARD [%s] tech p=%d available=[%s] researched=[%s]", t, tech.player, av, re);
    } else {
        ScLog("CARD [%s] tech p=%d UNREADABLE", t, (int)hdr.portraitOwner);
    }

    ScLog("CARD [%s] slots=%d shown=%d greyed=%d", t, hdr.slots, hdr.shown, hdr.greyed);
}
