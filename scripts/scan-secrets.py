#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

EMAIL_RE = re.compile(r'[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})')
SECRET_RE = re.compile(r'(gho_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_\-]+)', re.I)
ASSIGNMENT_RE = re.compile(r'(?i)\b(api[_-]?key|token|secret|password)\b\s*[:=]\s*["\'\`]?[^"\'\`\s]{4,}')
ALLOWLIST_EMAIL_DOMAINS = {'example.com'}
TEXT_EXTS = {
    '.md', '.txt', '.js', '.mjs', '.cjs', '.ts', '.tsx', '.jsx', '.json', '.yml', '.yaml', '.sh', '.bash', '.py', '.env.example', '.gitignore', '.LICENSE', ''
}
SKIP_DIRS = {'.git', 'node_modules', '.venv', 'dist', 'build'}


def is_text_path(path: Path) -> bool:
    if path.name in {'LICENSE', '.gitignore'}:
        return True
    suffixes = ''.join(path.suffixes)
    return path.suffix in TEXT_EXTS or suffixes in TEXT_EXTS


problems = []
for path in ROOT.rglob('*'):
    if path.is_dir():
        continue
    if any(part in SKIP_DIRS for part in path.parts):
        continue
    if not is_text_path(path):
        continue
    text = path.read_text(encoding='utf-8', errors='ignore')
    for i, line in enumerate(text.splitlines(), 1):
        for m in EMAIL_RE.finditer(line):
            full = m.group(0)
            domain = m.group(1).lower()
            if domain not in ALLOWLIST_EMAIL_DOMAINS:
                problems.append((path.relative_to(ROOT), i, 'email', full))
        for m in SECRET_RE.finditer(line):
            problems.append((path.relative_to(ROOT), i, 'token-like', m.group(0)[:16] + '...'))
        if ASSIGNMENT_RE.search(line):
            problems.append((path.relative_to(ROOT), i, 'secret-assignment', line.strip()[:120]))

if problems:
    for rel, line_no, kind, snippet in problems:
        print(f'{rel}:{line_no}: {kind}: {snippet}')
    sys.exit(1)

print('OK: no non-placeholder emails, token-like secrets, or suspicious secret assignments found')
