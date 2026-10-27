#!/usr/bin/env python3
"""Reject Tauri binaries that do not embed Vite's production assets."""
from pathlib import Path
import sys


if len(sys.argv) != 2:
    raise SystemExit("usage: check-tauri-production.py BINARY")

binary = Path(sys.argv[1])
if not binary.is_file():
    raise SystemExit(f"Tauri binary not found: {binary}")
if b"assets/index-" not in binary.read_bytes():
    raise SystemExit("Tauri binary does not contain the compiled frontend assets")

print("Tauri production asset check: PASS")
