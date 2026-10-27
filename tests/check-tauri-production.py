#!/usr/bin/env python3
"""Reject Tauri binaries that still load Vite's development server."""
from pathlib import Path
import sys


if len(sys.argv) != 2:
    raise SystemExit("usage: check-tauri-production.py BINARY")

binary = Path(sys.argv[1])
if not binary.is_file():
    raise SystemExit(f"Tauri binary not found: {binary}")
if b"http://localhost:1420" in binary.read_bytes():
    raise SystemExit("Tauri binary still targets the localhost development server")

print("Tauri production asset check: PASS")
