#!/usr/bin/env python3
"""Check the staged publication tree, without reading local user data."""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
def git(*args):
    return subprocess.check_output(['git', '-C', str(root), *args])

files = git('ls-files', '-z').decode().split('\0')
allowed_roots = {'macos', 'native-tests', 'scripts', 'docs', '.github', 'Sources', 'Tests'}
allowed_files = {'.gitignore', 'README.md', 'LICENSE', 'CONTRIBUTING.md',
                 'PRIVACY.md', 'THIRD_PARTY_NOTICES.md', 'Package.swift'}
blocked_parts = {'xcuserdata', 'build', 'verification', 'DerivedData', '.cursor'}
blocked_extensions = {'.log', '.zip', '.dmg', '.pkg', '.p12', '.p8', '.key',
                      '.mobileprovision', '.xcuserstate'}
patterns = [rb'/' + rb'Users/[^/\s]+/', rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY',
            rb'gh[pousr]_[A-Za-z0-9]{30,}', rb'github_pat_[A-Za-z0-9_]{30,}',
            rb'AKIA[0-9A-Z]{16}']
failures = []
count = 0
for name in filter(None, files):
    p = pathlib.PurePosixPath(name)
    if p.parts[0] not in allowed_roots and name not in allowed_files:
        failures.append(f'Unexpected file: {name}')
    if (set(p.parts) & blocked_parts or p.suffix in blocked_extensions
            or p.name.startswith(('workspace', '.env'))):
        failures.append(f'Private or generated file: {name}')
    data = git('show', ':' + name)
    if b'\0' not in data and any(re.search(pattern, data) for pattern in patterns):
        failures.append(f'Review sensitive content: {name}')
    count += 1
if failures:
    print('\n'.join(failures), file=sys.stderr)
    sys.exit(1)
print(f'Publication tree checked: {count} files; no prohibited artifacts or credential patterns.')
