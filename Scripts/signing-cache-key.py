#!/usr/bin/env python3
"""Identify dependency bytes and signing certificate; never access private keys."""
import hashlib
import os
from pathlib import Path
import sys


def cache_key(root, identity):
    digest = hashlib.sha256(identity.upper().encode() + b'\0')
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root).as_posix().encode()
        if path.is_symlink():
            digest.update(b'L\0' + relative + b'\0' + os.readlink(path).encode() + b'\0')
        elif path.is_file():
            digest.update(b'F\0' + relative + b'\0' + hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


if __name__ == '__main__':
    print(cache_key(Path(sys.argv[1]), sys.argv[2]))
