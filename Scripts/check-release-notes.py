#!/usr/bin/env python3
"""Fail release preparation when the visible What's New is stale or historical."""
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parent.parent
version = plistlib.loads((root / "Support/Info.plist").read_bytes())["CFBundleShortVersionString"]
source = (root / "Sources/Moon/WhatsNew.swift").read_text()
notes = source.split("static let notes: [Notes] = [", 1)[1].split("\n    ]", 1)[0]
versions = re.findall(r'Notes\(version: "([^"]+)"', notes)
if versions != [version]:
    raise SystemExit(f"What's New must contain only Moon {version}; found {versions}")
print(f"What's New matches Moon {version}; one current release.")
