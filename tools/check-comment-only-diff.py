"""Verify that only comments changed between two revisions of a file.
usage: codesame.py <ref> <file>...   (compares git <ref>:<file> with worktree file)
Exit 1 and print the first differing code token if code changed."""
import subprocess, sys, re, io, tokenize

BS = chr(92)

def strip_c(src):
    out = []; i = 0; n = len(src)
    while i < n:
        c = src[i]
        if c == '"' or c == "'":
            q = c; j = i + 1
            while j < n and src[j] != q:
                if src[j] == BS: j += 1
                j += 1
            out.append(src[i:j + 1]); i = j + 1
        elif src.startswith('//', i):
            j = src.find('\n', i); i = n if j < 0 else j
        elif src.startswith('/*', i):
            j = src.find('*/', i + 2); i = n if j < 0 else j + 2; out.append(' ')
        else:
            out.append(c); i += 1
    return ''.join(out)

PS_CMD = ('$src=[Console]::In.ReadToEnd(); $t=$null; '
          '[System.Management.Automation.Language.Parser]::ParseInput($src,[ref]$t,[ref]$null)|Out-Null; '
          '$t | Where-Object { $_.Kind -ne "Comment" -and $_.Kind -ne "NewLine" -and $_.Kind -ne "EndOfInput" } '
          '| ForEach-Object { $_.Text }')

def strip_ps1(src):
    r = subprocess.run(['pwsh', '-NoProfile', '-Command', PS_CMD], input=src,
                       capture_output=True, text=True, encoding='utf-8')
    if r.returncode != 0:
        raise SystemExit('pwsh tokenize failed: ' + r.stderr)
    return r.stdout

def strip_py(src):
    toks = []
    for t in tokenize.generate_tokens(io.StringIO(src).readline):
        if t.type == tokenize.COMMENT or t.type == tokenize.NL:
            continue
        if t.type in (tokenize.INDENT, tokenize.DEDENT, tokenize.NEWLINE):
            toks.append(tokenize.tok_name[t.type]); continue
        toks.append(t.string)
    return '\n'.join(toks)

def norm(ext, src):
    if ext in ('cpp', 'h', 'c', 'hpp', 'java'):
        s = strip_c(src)
    elif ext == 'ps1':
        return strip_ps1(src)
    elif ext == 'py':
        return strip_py(src)
    else:
        s = src
    return re.sub(r'\s+', ' ', s).strip()

ref = sys.argv[1]; bad = 0
for f in sys.argv[2:]:
    ext = f.rsplit('.', 1)[-1]
    old = subprocess.run(['git', 'show', f'{ref}:{f}'], capture_output=True, text=True,
                         encoding='utf-8', errors='replace').stdout
    new = open(f, encoding='utf-8', errors='replace').read()
    a, b = norm(ext, old), norm(ext, new)
    if a != b:
        bad += 1
        i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
        print(f'CODE CHANGED: {f}')
        print('  old: ' + repr(a[max(0, i - 80):i + 80]))
        print('  new: ' + repr(b[max(0, i - 80):i + 80]))
    else:
        print(f'ok: {f}')
sys.exit(1 if bad else 0)
