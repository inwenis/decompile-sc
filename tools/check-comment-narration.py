"""Fail when a code comment narrates history instead of stating a timeless why.

usage: python tools/check-comment-narration.py            # scan all tracked code files
       python tools/check-comment-narration.py FILE...    # scan given files
       python tools/check-comment-narration.py --selftest

Flags task ids, dates, PR/issue numbers and change-narration words inside comment
lines. Code lines (test names, log strings) are never inspected. History belongs in
the PR body, git log, or research/*.md; a comment says why the code is the way it is.
"""
import io
import re
import subprocess
import sys
import tokenize

MARK = {'ps1': '#', 'py': '#', 'cpp': '//', 'h': '//', 'java': '//'}
NARR = re.compile(
    r'\btask ?\d{3}\b|\bt0\d\d\b|\b(?:PR|issue) #\d+|\b20\d\d-\d\d-\d\d\b'
    r'|\b(?:previously|originally|used to|no longer|before this task|this task)\b', re.I)


def scan_py(path, src):
    """Comment TOKENS only: a '#' inside a python string is code, not a comment."""
    hits = []
    for t in tokenize.generate_tokens(io.StringIO(src).readline):
        if t.type != tokenize.COMMENT:
            continue
        m = NARR.search(t.string)
        if m:
            hits.append((path, t.start[0], m.group(0), t.string[:100]))
    return hits


def scan(path):
    ext = path.rsplit('.', 1)[-1]
    if ext not in MARK:
        return []
    if ext == 'py':
        src = open(path, encoding='utf-8', errors='replace').read()
        try:
            return scan_py(path, src)
        except (tokenize.TokenError, IndentationError, SyntaxError):
            pass  # unparseable: fall through to the line scan rather than skip the file
    mark = MARK[ext]
    hits = []
    in_block = False
    in_herestring = False
    for n, line in enumerate(open(path, encoding='utf-8', errors='replace'), 1):
        s = line.strip()
        if ext == 'ps1':  # a here-string is code even when its lines look like comments
            if in_herestring:
                if s in ("'@", '"@'):
                    in_herestring = False
                continue
            if s.endswith("@'") or s.endswith('@"'):
                in_herestring = True
                continue
        if in_block:
            text = s
            if (ext == 'ps1' and '#>' in s) or (ext != 'ps1' and '*/' in s):
                in_block = False
        elif s.startswith('<#') or s.startswith('/*'):
            text = s
            in_block = not (('#>' in s) if ext == 'ps1' else ('*/' in s))
        elif s.startswith(mark):
            text = s
        elif mark in line:
            text = line.split(mark, 1)[1]  # ponytail: trailing comment split ignores strings containing the marker
        else:
            continue
        m = NARR.search(text)
        if m:
            hits.append((path, n, m.group(0), s[:100]))
    return hits


def selftest():
    import tempfile, os
    good = "# the engine re-asserts this flag every frame\nx = 1  # bounded by the ring size\n"
    bad = "# task 061 removed the guard\nx = 1  # previously this was 2\n"
    quoted = "s = '# task 0" + "61 in a string is code'\n"  # a marker inside a string is code
    for src, expect in ((good, 0), (bad, 2), (quoted, 0)):
        fd, p = tempfile.mkstemp(suffix='.py'); os.write(fd, src.encode()); os.close(fd)
        got = len(scan(p)); os.unlink(p)
        assert got == expect, (src, got, expect)
    print('selftest ok')


if __name__ == '__main__':
    if '--selftest' in sys.argv:
        selftest(); sys.exit(0)
    files = sys.argv[1:] or subprocess.check_output(['git', 'ls-files'], text=True).split()
    hits = [h for f in files for h in scan(f)]
    for path, n, what, text in hits:
        print(f'{path}:{n}: "{what}" in comment: {text}')
    print(f'{len(hits)} narrating comment line(s)')
    sys.exit(1 if hits else 0)
