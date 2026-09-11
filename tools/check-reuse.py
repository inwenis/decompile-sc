#!/usr/bin/env python3
"""check-reuse -- fail a PR that adds a new copy of code we already have.

WHY A BLOCK SCAN AND NOT A NAME SCAN. Issue #130's cleanup found twelve copies of one
three-line function by reading, and then walked straight past three more copies of the
memory probe because their signatures differed: `SafeRead(const void*, void*, size_t)`,
`RangeReadable(const void*, size_t)` and `DefaultRead(DWORD, void*, size_t)` are the same
VirtualQuery three ways. Names are what the eye already catches. Identical BLOCKS are
what it does not, and two of those three copies had drifted apart on the low-end bounds
check by the time anyone looked. The PowerShell suites had Assert-That 26 times over.

THE SCAN is jscpd (https://github.com/kucherenko/jscpd), run through npx in its
comment-skipping mode: two copies are one block when their TOKENS agree, so re-indenting
a copy or re-wording its trailing comments does not make it a different block.

WHAT IT REPORTS, per target:

  cpp   tools/plugin/src/*.cpp, *.h     block, name, define, va
  ps1   tools/plugin/*.ps1              block

  block   MIN_LINES or more lines, MIN_TOKENS or more tokens, the same in two files
  name    one `static` function name defined in two different files
  define  one #define, name and body, in two different files
  va      a bare engine address literal in code outside sc_addresses.h

A block copied inside ONE file is not reported: hooktest.cpp builds a fake engine image
the same way in every part on purpose, and the rule this enforces is "never copy a helper
into a SECOND file".

THE BASELINE. This starts life with findings already in the tree -- some are deliberate
(a two-line test seam each module must own) and some are real but too big for the commit
that adds this tool. tools/check-reuse.<target>.baseline lists what was already there,
by a hash of the finding, so the gate is "no NEW duplication" from day one instead of a
wall of red nobody can act on. Shrinking the baseline is the job; growing it needs a
reason in the PR.

    python tools/check-reuse.py                    # check, exit 1 on a new finding
    python tools/check-reuse.py --list             # print every finding, exit 0
    python tools/check-reuse.py --update-baseline  # accept what is there now

Needs Node.js on PATH for npx; the first run downloads jscpd into npx's cache.
"""

import fnmatch
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

JSCPD = "jscpd@5.2.0"
# Five lines is the shortest run that is a copied idea rather than a shared idiom: a
# for-loop header plus a body reaches it, `return false; }` does not. 25 tokens keeps a
# five-line run of closing braces from counting.
MIN_LINES = 5
MIN_TOKENS = 25

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
        self.span = span              # list of (file, first line, last line)

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


def collect_blocks(files, target):
    """Every cross-file clone jscpd reports. A block in N files comes back as N-1 pairs
    with the same summary, which the baseline sees as one key."""
    if not files:
        return []
    npx = shutil.which("npx")
    if not npx:
        sys.exit("check-reuse: npx not found -- the block scan needs Node.js on PATH")
    out = pathlib.Path(tempfile.mkdtemp(prefix="check-reuse-"))
    cmd = [npx, "--yes", JSCPD, str(target["root"]), "--pattern", target["pattern"],
           "--reporters", "json", "--output", str(out), "--mode", "weak", "--silent",
           "--min-lines", str(MIN_LINES), "--min-tokens", str(MIN_TOKENS)]
    if target["skip"]:
        cmd += ["--ignore", ",".join("**/" + s for s in target["skip"])]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
    report = json.loads((out / "jscpd-report.json").read_text(encoding="utf-8"))
    shutil.rmtree(out, ignore_errors=True)

    sig = {p.name: dict(lines) for p, lines in files.items()}

    def code_lines(name, f):
        """The significant lines a clone covers: jscpd skipped `//` and `#` comment
        tokens, but not a `<# #>` block, and it cannot know that a shared include list
        is not duplication. A copy has to be MIN_LINES of code on BOTH sides."""
        span = range(f["startLoc"]["line"], f["endLoc"]["line"] + 1)
        return [l for l in (sig.get(name, {}).get(n) for n in span) if l]

    findings = []
    for d in report["duplicates"]:
        a, b = d["firstFile"], d["secondFile"]
        an, bn = pathlib.Path(a["name"]).name, pathlib.Path(b["name"]).name
        if an == bn:
            continue
        sides = [code_lines(an, a), code_lines(bn, b)]
        if min(map(len, sides)) < MIN_LINES:
            continue
        findings.append(Finding(
            "block",
            "%d identical lines: %s" % (d["lines"], sides[0][0][:70]),
            sorted("%s:%d" % (n, f["startLoc"]["line"]) for n, f in ((an, a), (bn, b))),
            [(n, f["startLoc"]["line"], f["endLoc"]["line"]) for n, f in ((an, a), (bn, b))]))
    return findings


def collect_names(files, target):
    """One `static` name whose BODY is also the same, in two files.

    Name alone is not a finding: `static` is file-local, so two modules may each have a
    private CollectGarbage doing genuinely different things -- sc_prodqueue refunds and
    sc_upgrades must not. What is a finding is the same name over the same body, which
    is a copy that the block scan misses when the copy is shorter than MIN_LINES.
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


def collect_defines(files, target):
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


def collect_vas(files, target):
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
         pattern="*.{cpp,h}", comment="//", block=("/*", "*/"), ignore=("#include",),
         # Generated, or a table of evidence rather than code.
         skip={"sc_screen_patches_*.h", "sc_addresses.h"},   # generated tables: same instructions, different immediates
         collectors=(collect_blocks, collect_names, collect_defines, collect_vas)),
    dict(name="ps1", root=pathlib.Path("tools/plugin"), globs=("*.ps1",), pattern="*.ps1",
         comment="#", block=("<#", "#>"), ignore=(), skip=set(),
         collectors=(collect_blocks,)),
]


def copied(files, findings):
    """How much of the tree sits inside a reported block: the number a reuse PR moves.
    Counted over significant lines, so a copied comment or blank line is not credit."""
    sig = {p.name: {n for n, _ in lines} for p, lines in files.items()}
    total = sum(len(s) for s in sig.values())
    inside = {(name, n) for f in findings for name, first, last in f.span
              for n in range(first, last + 1) if n in sig.get(name, ())}
    return "%d of %d lines (%d%%) inside a copied block" % (
        len(inside), total, 100 * len(inside) // max(total, 1))


def check(target, args):
    tag = "check-reuse [%s]" % target["name"]
    files = {p: significant(p, target)
             for g in target["globs"] for p in sorted(target["root"].glob(g))
             if not any(fnmatch.fnmatch(p.name, s) for s in target["skip"])}
    findings = [f for collect in target["collectors"] for f in collect(files, target)]
    findings.sort(key=lambda f: (f.kind, f.summary, f.where))
    baseline = pathlib.Path("tools/check-reuse.%s.baseline" % target["name"])

    if args.list:
        for f in findings:
            print(f)
        print("\n%s: %d finding(s) in %d files; %s\n" % (
            tag, len(findings), len(files), copied(files, findings)))
        return 0

    if args.update_baseline:
        seen, entries = set(), []
        for f in findings:
            if f.key not in seen:
                seen.add(f.key)
                entries.append("%s  # %s\n" % (f.key, f.summary))
        baseline.write_text(
            "# check-reuse baseline for %s -- what was already duplicated when the gate\n"
            "# went in. One line per accepted finding. SHRINKING this file is the job;\n"
            "# growing it needs a reason in the PR that grows it.\n" % target["name"]
            + "".join(entries), encoding="utf-8")
        print("%s: baseline written with %d finding(s)" % (tag, len(entries)))
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
