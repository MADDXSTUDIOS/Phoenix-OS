#!/usr/bin/env python3
"""Rebuild manifest.txt (the installer's file list). Run after adding or removing files."""
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
files = ["startup.lua"]
for top in ("system", "lib", "apps"):
    for base, dirs, names in os.walk(os.path.join(REPO, top)):
        dirs.sort()
        for name in sorted(names):
            files.append(os.path.relpath(os.path.join(base, name), REPO).replace(os.sep, "/"))
with open(os.path.join(REPO, "manifest.txt"), "w") as f:
    f.write("# Files the installer downloads. Rebuild with: python3 tools/mkmanifest.py\n")
    f.write("\n".join(files) + "\n")
print(len(files), "files")
