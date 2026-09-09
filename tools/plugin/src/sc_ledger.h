// sc_ledger.h -- the array-of-records bookkeeping sc_prodqueue and sc_upgrades both do.
//
// Both modules hold a small fixed array of per-building records, both look one up by
// CUnit*, both drop one by swapping the last entry over it, and both add up the items
// across every record when a game ends. Those three were written out twice, character
// for character, over two record types that differ only in what they carry.
//
// SHARED HERE: the mechanism. NOT shared, deliberately: the policy on top of it --
// sc_prodqueue REFUNDS a dropped record's items and sc_upgrades must not (a held
// upgrade was never paid for), and each keeps its own frozen `PRODQEV`/`UPGQEV` log
// text that a .ps1 suite parses -- handed in, never composed here. Those look similar
// and are not the same, and folding them together behind a callback would hide exactly
// the difference that matters.
//
// Templates rather than a `void*` and a stride: the record types are known at every
// call site, so the compiler can do the arithmetic and the type checking that a stride
// parameter would move into a comment. Nothing here allocates, throws or has state.
// A record type only has to have a `DWORD unit` and an `int count`.

#ifndef SC_LEDGER_H
#define SC_LEDGER_H

#include <windows.h>

#include "sc_log.h"
#include "sc_session.h"

// The record for `unit`, or NULL. Linear over a handful of entries: the arrays are 32
// records and the lookup runs inside a detour, so a scan beats anything with a bucket.
template <class Record>
inline Record* ScLedgerFind(Record* rec, int count, DWORD unit) {
    for (int i = 0; i < count; ++i) {
        if (rec[i].unit == unit) return &rec[i];
    }
    return NULL;
}

// Remove record `i` by moving the LAST one over it. The order of the array carries no
// meaning -- a record is found by its unit pointer, never by its position -- so this is
// the cheap removal, and dropping the last record is the self-assignment case that
// falls out correctly rather than being special-cased. Out of range is a no-op.
template <class Record>
inline void ScLedgerDropAt(Record* rec, int* count, int i) {
    if (i < 0 || i >= *count) return;
    rec[i] = rec[*count - 1];
    --*count;
}

// How many items the whole ledger is holding. Both modules report this when a game ends
// -- the number of queued things that just stopped existing.
template <class Record>
inline int ScLedgerItemCount(const Record* rec, int count) {
    int items = 0;
    for (int i = 0; i < count; ++i) items += rec[i].count;
    return items;
}

// THE EPOCH TEST (sc_session.h). A record made in a game that has ended must not
// survive into the next one, and nothing the record carries can tell: a save restores
// unit pointer, uniqueness, player and hitpoints verbatim into the same seat of the
// same static array. Only the epoch changes. Drops every record, logs the module's own
// line when there was anything to drop (`fmt` takes: old epoch, new epoch, records,
// items) and returns the item count for the module's own counter. NOTHING is refunded
// on this path in either module: whatever was paid was paid in a game whose player
// state is gone, and paying it into the loaded game hands out free units.
template <class Record>
inline int ScLedgerSessionSync(const Record* rec, int* count, unsigned* session,
                               const char* fmt) {
    const unsigned now = ScSessionEpoch();
    if (*session == now) return 0;
    const int items = ScLedgerItemCount(rec, *count);
    if (*count > 0) ScLog(fmt, *session, now, *count, items);
    *count = 0;
    *session = now;
    return items;
}

#endif // SC_LEDGER_H
