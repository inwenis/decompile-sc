#!/usr/bin/env python3
"""check-reuse -- fail a PR that adds a new copy of code we already have.

WHY A BLOCK SCAN AND NOT A NAME SCAN. Issue #130's cleanup found twelve copies of one
three-line function by reading, and then walked straight past three more copies of the
memory probe because their signatures differed: `SafeRead(const void*, void*, size_t)`,
`RangeReadable(const void*, size_t)` and `DefaultRead(DWORD, void*, size_t)` are the same
VirtualQuery three ways. Names are what the eye already catches. Identical BLOCKS are
what it does not, and two of those three copies had drifted apart on the low-end bounds
check by the time anyone looked. The same scan over the PowerShell suites found
Assert-That copied 26 times.

WHAT IT REPORTS, per target:

  cpp   tools/plugin/src/*.cpp, *.h     block, name, define, va
  ps1   tools/plugin/*.ps1              block

  block   MIN_BLOCK or more consecutive identical lines in two different files
  name    one `static` function name defined in two different files
  define  one #define, name and body, in two different files
  va      a bare engine address literal in code outside sc_addresses.h

Comments, blank lines and #include lines are ignored: a copied comment is a different
problem (tools/check-comment-narration.py) and a shared include list is not duplication.

THE BASELINE. This starts life with findings already in the tree -- some are deliberate
(a two-line test seam each module must own) and some are real but too big for the commit
that adds this tool. tools/check-reuse.<target>.baseline lists what was already there,
by a hash of the finding, so the gate is "no NEW duplication" from day one instead of a
wall of red nobody can act on. Shrinking the baseline is the job; growing it needs a
reason in the PR.

    python tools/check-reuse.py                    # check, exit 1 on a new finding
    python tools/check-reuse.py --list             # print every finding, exit 0
    python tools/check-reuse.py --update-baseline  # accept what is there now
"""

import argparse
import hashlib
import pathlib
import re
import sys

# Five lines is the shortest run that is a copied idea rather than a shared idiom: a
# for-loop header plus a body reaches it, `return false; }` does not.
MIN_BLOCK = 5

VA = re.compile(r"\b0x00(4[0-9A-Fa-f]{5}|5[0-9A-Fa-f]{5}|6[0-9A-Fa-f]{5})\b")
# An address inside a log line is evidence being quoted, not an address being used.
STRING = re.compile(r'"(?:[^"\\]|\\.)*"')
# `static void __attribute__((stdcall)) SC_GAME_ENTRY Foo(...)` puts three things between
# `static` and the name; strip them so the name that comes out is the function's.
NOISE = re.compile(r"__attribute__\s*\(\([^)]*\)\)|\bSC_GAME_ENTRY\b|\bWINAPI\b")
STATIC_FN = re.compile(
    r"^static\s+(?:inline\s+)?[A-Za-z_][A-Za-z0-9_:<>* ]*?\b([A-Za-z_][A-Za-z0-9_]*)\s*\("
)
DEFINE = re.compile(r"^#define\s+([A-Za-z_][A-Za-z0-9_]*)(?:\([^)]*\))?\s+(.+?)\s*$")


class Finding:
    def __init__(self, kind, summary, where, span=()):
        self.kind = kind
        self.summary = summary
        self.where = where            # list of "file:line"
        self.span = span              # list of (file, index into significant(), length)

    @property
    def key(self):
        h = hashlib.sha256(("%s\n%s" % (self.kind, self.summary)).encode()).hexdigest()
        return "%s %s" % (self.kind, h[:16])

    def __str__(self):
        return "%-6s %s\n         %s" % (self.kind, self.summary, "  ".join(self.where))


def significant(path, target):
    """(line_number, stripped_text) for lines worth comparing."""
    out, in_block = [], False
    open_, close = target["block"]
    for n, raw in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        s = raw.strip()
        if in_block:
            in_block = close not in s
            continue
        if s.startswith(open_):
            in_block = close not in s[len(open_):]
            continue
        if not s or s.startswith(target["comment"]) or s.startswith(target["ignore"]):
            continue
        out.append((n, s))
    return out


def collect_blocks(files):
    """Every run of >= MIN_BLOCK identical consecutive lines shared by two files."""
    # index every window by its text, then keep the longest run per (file, start).
    windows = {}
    for path, lines in files.items():
        for i in range(len(lines) - MIN_BLOCK + 1):
            text = "\n".join(t for _, t in lines[i:i + MIN_BLOCK])
            windows.setdefault(text, []).append((path.name, lines[i][0], i))

    by_name = {p.name: lines for p, lines in files.items()}

    def agrees(hits, offset):
        """Do all hits still hold the same line `offset` lines from their start?"""
        seen = set()
        for name, _, idx in hits:
            lines = by_name[name]
            j = idx + offset
            if j < 0 or j >= len(lines):
                return False
            seen.add(lines[j][1])
        return len(seen) == 1

    findings = []
    for text, hits in windows.items():
        if len({n for n, _, _ in hits}) < 2:
            continue
        # Report a run ONCE, at its start. A window whose preceding line also agrees is
        # the middle of a longer run somebody else already reported; a 12-line copy
        # should be one finding, not eight overlapping five-line ones.
        if agrees(hits, -1):
            continue
        grown = MIN_BLOCK
        while agrees(hits, grown):
            grown += 1
        findings.append(Finding(
            "block",
            "%d identical lines: %s" % (grown, text.split("\n")[0][:70]),
            sorted("%s:%d" % (n, ln) for n, ln, _ in hits),
            [(n, idx, grown) for n, _, idx in hits]))
    return findings


def collect_names(files):
    """One `static` name whose BODY is also the same, in two files.

    Name alone is not a finding: `static` is file-local, so two modules may each have a
    private CollectGarbage doing genuinely different things -- sc_prodqueue refunds and
    sc_upgrades must not. What is a finding is the same name over the same body, which
    is a copy that the block scan misses when the copy is shorter than MIN_BLOCK.
    """
    defs = {}
    for path, lines in files.items():
        for i, (n, text) in enumerate(lines):
            m = STATIC_FN.match(NOISE.sub(" ", text).strip())
            if not m:
                continue
            body = "|".join(t for _, t in lines[i:i + 4])   # signature + up to 3 lines
            defs.setdefault((m.group(1), body), []).append("%s:%d" % (path.name, n))
    out = []
    for (name, _body), where in defs.items():
        if len({w.split(":")[0] for w in where}) > 1:
            out.append(Finding("name", "static %s() -- same name AND same body in %d files"
                               % (name, len({w.split(':')[0] for w in where})), sorted(where)))
    return out


def collect_defines(files):
    defs = {}
    for path, lines in files.items():
        for n, text in lines:
            m = DEFINE.match(text)
            if m:
                defs.setdefault((m.group(1), m.group(2)), []).append("%s:%d" % (path.name, n))
    out = []
    for (name, body), where in defs.items():
        if len({w.split(":")[0] for w in where}) > 1:
            out.append(Finding("define", "#define %s %s -- in %d files"
                               % (name, body[:40], len({w.split(':')[0] for w in where})),
                               sorted(where)))
    return out


def collect_vas(files):
    """A bare engine address the plugin USES. Three things that look like one are not:

      * an address in a trailing comment or a log line -- that is evidence, quoted;
      * a #define -- naming it is the fix, so the fix cannot be the finding;
      * hooktest.cpp's fixture tables, which are built FROM the engine's own card data
        (condition and action pointers copied verbatim). Those are the values under
        test, not addresses this code dereferences.
    """
    out = []
    for path, lines in files.items():
        if path.name == "hooktest.cpp":
            continue
        for n, text in lines:
            if text.startswith("#define"):
                continue
            code = STRING.sub('""', text).split("//")[0]
            for m in VA.finditer(code):
                out.append(Finding(
                    "va", "bare engine address %s -- name it in sc_addresses.h" % m.group(0),
                    ["%s:%d" % (path.name, n)]))
    return out


TARGETS = [
    dict(name="cpp", root=pathlib.Path("tools/plugin/src"), globs=("*.cpp", "*.h"),
         comment="//", block=("/*", "*/"), ignore=("#include",),
         # Generated, or a table of evidence rather than code.
         skip={"sc_screen_patches.h", "sc_addresses.h"},
         collectors=(collect_blocks, collect_names, collect_defines, collect_vas)),
    dict(name="ps1", root=pathlib.Path("tools/plugin"), globs=("*.ps1",),
         comment="#", block=("<#", "#>"), ignore=(), skip=set(),
         collectors=(collect_blocks,)),
]


def copied(files, findings):
    """How much of the tree sits inside a reported block: the number a reuse PR moves."""
    total = sum(len(lines) for lines in files.values())
    inside = {(name, i) for f in findings for name, idx, length in f.span
              for i in range(idx, idx + length)}
    return "%d of %d lines (%d%%) inside a copied block" % (
        len(inside), total, 100 * len(inside) // max(total, 1))


def check(target, args):
    tag = "check-reuse [%s]" % target["name"]
    files = {p: significant(p, target)
             for g in target["globs"] for p in sorted(target["root"].glob(g))
             if p.name not in target["skip"]}
    findings = [f for collect in target["collectors"] for f in collect(files)]
    findings.sort(key=lambda f: (f.kind, f.summary))
    baseline = pathlib.Path("tools/check-reuse.%s.baseline" % target["name"])

    if args.list:
        for f in findings:
            print(f)
        print("\n%s: %d finding(s) in %d files; %s\n" % (
            tag, len(findings), len(files), copied(files, findings)))
        return 0

    if args.update_baseline:
        baseline.write_text(
            "# check-reuse baseline for %s -- what was already duplicated when the gate\n"
            "# went in. One line per accepted finding. SHRINKING this file is the job;\n"
            "# growing it needs a reason in the PR that grows it.\n" % target["name"]
            + "".join("%s  # %s\n" % (f.key, f.summary) for f in findings),
            encoding="utf-8")
        print("%s: baseline written with %d finding(s)" % (tag, len(findings)))
        return 0

    accepted = set()
    if baseline.exists():
        for line in baseline.read_text(encoding="utf-8").splitlines():
            line = line.split("#")[0].strip() if not line.startswith("#") else ""
            if line:
                accepted.add(line)

    new = [f for f in findings if f.key not in accepted]
    stale = accepted - {f.key for f in findings}

    for f in new:
        print("%s: NEW %s" % (tag, f))
    if new:
        print("\n%d new finding(s). Share the code, or -- if this copy is deliberate --\n"
              "run `python tools/check-reuse.py --update-baseline` and say why in the PR."
              % len(new))
        return 1

    print("%s: %d finding(s), all in the baseline; %s"
          % (tag, len(findings), copied(files, findings)))
    if stale:
        print("%s: %d baseline entr%s no longer found -- run --update-baseline to shrink it"
              % (tag, len(stale), "y" if len(stale) == 1 else "ies"))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true", help="print every finding and exit 0")
    ap.add_argument("--update-baseline", action="store_true",
                    help="rewrite the baselines from what is in the tree now")
    args = ap.parse_args()

    if not TARGETS[0]["root"].is_dir():
        print("check-reuse: %s not found -- run me from the repo root" % TARGETS[0]["root"])
        return 2
    return max(check(t, args) for t in TARGETS)


if __name__ == "__main__":
    sys.exit(main())
